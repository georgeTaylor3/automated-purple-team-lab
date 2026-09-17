"""
Demo controller -- Increment 1.

Two endpoints, both operating on a single Firestore document that
tracks whether the lab is currently claimed. This increment does NOT
yet talk to CALDERA, does NOT yet have real timers (Cloud Tasks comes
in a later increment) -- the only goal here is proving Cloud Run and
Firestore work correctly together, with the actual concurrency-safety
mechanism (a Firestore transaction) built and tested from the start,
since that's the one piece genuinely hard to retrofit later.

GET  /status  -- read-only, safe to call anytime, no side effects.
                 Used by the frontend to decide what to show a visitor
                 on page load (buttons, or a "come back later" message).

POST /claim   -- the actual claiming action. Uses a Firestore
                 transaction so that if two visitors' requests arrive
                 at nearly the same instant, only one of them can
                 successfully claim the lab -- the other gets told
                 it's already taken, rather than both believing they
                 succeeded.
"""

import os
import uuid
from datetime import datetime, timezone

from flask import Flask, jsonify, request
from google.cloud import firestore

app = Flask(__name__)

# A single Firestore client, reused across requests within one Cloud
# Run instance's lifetime (Cloud Run may keep an instance "warm" for a
# short time after a request, reusing it for the next one rather than
# cold-starting every single time -- this client object persists
# across those reuses, which is the recommended pattern).
db = firestore.Client()

# Every visitor session reads/writes the SAME one document -- this
# project doesn't need a full collection of many documents for this
# part, just one shared piece of state everyone contends over.
STATE_DOC = db.collection("lab_state").document("current")


@app.errorhandler(500)
def handle_error(e):
    # Scoped to 500 (genuine server errors) specifically, not
    # @app.errorhandler(Exception) -- that broader version was also
    # catching Flask's own normal routing errors (like a plain 404 for
    # an unknown URL) and masking them as a scary "internal error",
    # discovered for real on 2026-09-12 when a redeploy hadn't
    # actually happened yet and a routine 404 got hidden this way.
    app.logger.exception("Unhandled error")
    return jsonify({"error": "internal error"}), 500


@app.errorhandler(400)
def handle_bad_request(e):
    return jsonify({"error": "bad request"}), 400


@app.errorhandler(404)
def handle_not_found(e):
    return jsonify({"error": "not found"}), 404


@app.errorhandler(429)
def handle_rate_limited(e):
    return jsonify({"error": "too many requests, please slow down"}), 429


def utcnow_iso():
    return datetime.now(timezone.utc).isoformat()


@app.route("/status", methods=["GET"])
def status():
    """Read-only check of current lab state. No side effects -- safe
    to call as often as needed, e.g. every time a visitor's browser
    loads the page."""
    doc = STATE_DOC.get()
    if not doc.exists:
        # First-ever request against a brand-new Firestore database --
        # the document genuinely doesn't exist yet. Treat this the
        # same as "idle".
        return jsonify({"state": "idle", "session_id": None})

    data = doc.to_dict()
    return jsonify(data)


@app.route("/claim", methods=["POST"])
def claim():
    """Attempt to claim the lab. Uses a Firestore TRANSACTION -- this
    is the actual mechanism preventing two visitors from both
    successfully claiming at once.

    Why a transaction is necessary, not just a plain read-then-write:
    without one, two nearly-simultaneous requests could BOTH read
    "idle" before either has written anything back -- both would then
    think they succeeded and both write "active", silently
    overwriting each other. A transaction makes the read-check-write
    sequence atomic: Firestore guarantees that if two transactions
    touch the same document at the same time, one of them is forced
    to retry against the NEW state, rather than both proceeding blind.
    """

    @firestore.transactional
    def try_claim(transaction):
        snapshot = STATE_DOC.get(transaction=transaction)
        current_state = snapshot.to_dict() if snapshot.exists else {"state": "idle"}

        if current_state.get("state") not in (None, "idle"):
            # Someone already has it (or it's in cooldown -- treated
            # the same way for now; cooldown-expiry logic comes in a
            # later increment). Don't grant a new claim.
            return None

        new_session_id = str(uuid.uuid4())
        transaction.set(STATE_DOC, {
            "state": "active",
            "session_id": new_session_id,
            "claimed_at": utcnow_iso(),
            "first_attack_at": None,
        })
        return new_session_id

    transaction = db.transaction()
    session_id = try_claim(transaction)

    if session_id is None:
        return jsonify({"claimed": False, "reason": "lab already in use"}), 409

    return jsonify({"claimed": True, "session_id": session_id})

# -----------------------------------------------------------------------
# /attack -- Increment 2.
# -----------------------------------------------------------------------

import requests
from google.cloud import secretmanager

# Visitor-supplied scenario names map to real, pre-approved CALDERA
# adversary IDs. Visitor input is only ever used as a dictionary key --
# it never reaches CALDERA directly. Anything not in this dict is
# rejected before any network call happens.
APPROVED_SCENARIOS = {
    "discovery": {
        "adversary_id": "0f4c3c67-845e-49a0-927e-90ed33c044e0",
        "group": "workstation-red",
    },
    "juice-shop-sqli": {
        "adversary_id": "14db9072-5406-4645-ba34-f7d9a25b1fd5",
        "group": "workstation-red",
    },
}

CALDERA_URL = "http://10.60.10.39:8888"
ATTACK_COOLDOWN_SECONDS = 60

_secret_client = secretmanager.SecretManagerServiceClient()
_cached_caldera_password = None


def get_caldera_password():
    # Cached at the module level -- fetched once per Cloud Run
    # instance's cold start, reused across warm invocations. Avoids a
    # Secret Manager round-trip on every single request.
    global _cached_caldera_password
    if _cached_caldera_password is None:
        project_id = os.environ["PROJECT_ID"]
        name = f"projects/{project_id}/secrets/caldera-red-password/versions/latest"
        response = _secret_client.access_secret_version(name=name)
        _cached_caldera_password = response.payload.data.decode("UTF-8")
    return _cached_caldera_password


@app.route("/attack", methods=["POST"])
def attack():
    data = request.get_json(silent=True)
    if not data or "session_id" not in data or "scenario" not in data:
        return jsonify({"error": "session_id and scenario required"}), 400

    session_id = data["session_id"]
    scenario = data["scenario"]

    if scenario not in APPROVED_SCENARIOS:
        return jsonify({"error": "unknown scenario"}), 400
    scenario_config = APPROVED_SCENARIOS[scenario]
    adversary_id = scenario_config["adversary_id"]
    caldera_group = scenario_config["group"]

    # Transaction 1: validate the session, check the cooldown, and
    # reserve the slot (write last_attack_at) BEFORE the slow CALDERA
    # call. This closes the double-click race: two near-simultaneous
    # requests can't both pass the cooldown check, since the first one
    # to commit the transaction updates last_attack_at immediately,
    # and Firestore forces the second to retry against that new value.
    @firestore.transactional
    def try_reserve(transaction):
        snapshot = STATE_DOC.get(transaction=transaction)
        if not snapshot.exists:
            return "no_session"
        current = snapshot.to_dict()

        if current.get("session_id") != session_id:
            return "invalid_session"

        last_attack = current.get("last_attack_at")
        if last_attack:
            elapsed = (
                datetime.now(timezone.utc) - datetime.fromisoformat(last_attack)
            ).total_seconds()
            if elapsed < ATTACK_COOLDOWN_SECONDS:
                return f"cooldown:{int(ATTACK_COOLDOWN_SECONDS - elapsed)}"

        now = utcnow_iso()
        update = {"last_attack_at": now}
        if current.get("first_attack_at") is None:
            update["first_attack_at"] = now
        transaction.update(STATE_DOC, update)
        return "ok"

    reserve_result = try_reserve(db.transaction())

    if reserve_result in ("no_session", "invalid_session"):
        return jsonify({"error": "invalid or expired session"}), 400
    if reserve_result.startswith("cooldown:"):
        wait_seconds = reserve_result.split(":")[1]
        return jsonify({
            "error": f"please wait {wait_seconds}s before launching another attack"
        }), 429

    # Real CALDERA call -- deliberately outside any Firestore
    # transaction. Transactions should stay fast and pure; a slow
    # external network call inside one risks unnecessary retries or
    # timeouts.
    caldera_session = requests.Session()
    caldera_password = get_caldera_password()

    caldera_session.post(
        f"{CALDERA_URL}/enter",
        data={"username": "red", "password": caldera_password},
        timeout=10,
    )

    launch_resp = caldera_session.post(
        f"{CALDERA_URL}/api/v2/operations",
        json={
            "name": f"demo-{scenario}-{uuid.uuid4().hex[:8]}",
            "adversary": {"adversary_id": adversary_id},
            "group": caldera_group,
            "state": "running",
            "autonomous": 1,
        },
        timeout=15,
    )

    if launch_resp.status_code not in (200, 201):
        return jsonify({"error": "failed to launch attack"}), 500

    operation_id = launch_resp.json().get("id")

    # Transaction 2: record the successful launch, now that we have a
    # real operation ID to store.
    @firestore.transactional
    def record_attack(transaction):
        transaction.update(STATE_DOC, {
            "attacks": firestore.ArrayUnion([{
                "scenario": scenario,
                "operation_id": operation_id,
                "launched_at": utcnow_iso(),
            }])
        })

    record_attack(db.transaction())

    return jsonify({"launched": True, "operation_id": operation_id})


if __name__ == "__main__":
    # Cloud Run sets the PORT environment variable itself and expects
    # the container to listen on it -- 8080 is just a safe local
    # fallback for testing outside Cloud Run.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
