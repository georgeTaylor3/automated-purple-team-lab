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

from flask import Flask, jsonify
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


@app.errorhandler(Exception)
def handle_error(e):
    # A public-facing endpoint should never show a raw stack trace or
    # internal error detail to a random visitor. 
    # Log the real detail server-side (visible in Cloud
    # Run's own logs, which only I can see), and return a generic
    # message to whoever made the request.
    app.logger.exception("Unhandled error")
    return jsonify({"error": "internal error"}), 500


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


if __name__ == "__main__":
    # Cloud Run sets the PORT environment variable itself and expects
    # the container to listen on it -- 8080 is just a safe local
    # fallback for testing outside Cloud Run.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
