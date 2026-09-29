#!/usr/bin/env python3
# ensure-fleet-policies.py
#
# Stateless re-provisioning for Fleet agent policies and their
# integrations, mirroring ensure-caldera-abilities.sh's pattern:
# check whether each policy already exists by its known ID; if not,
# recreate it from committed, captured JSON rather than hand-building
# the payload again.
#
# The committed JSON files are RAW captures from GET
# /api/fleet/agent_policies/{id} -- genuine, working Kibana output,
# not a reconstructed guess. Elastic Defend's integration config
# especially is never reconstructed here; every field survives
# untouched except the specific, confirmed-read-only ones stripped
# below (version tokens, timestamps, live counts) -- fields Kibana's
# own response includes but its create endpoints reject.
#
# Two-call sequence per policy, matching exactly how these were
# originally built through the UI: POST /api/fleet/agent_policies
# creates the base policy (no integrations yet), then one
# POST /api/fleet/package_policies call per captured integration.

import json
import subprocess
import sys
import os

CALDERA_URL = "http://localhost:5601"
CAPTURE_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "fleet-policy-captures"
)

# Confirmed read-only fields on the top-level agent policy object --
# present in GET responses, rejected or ignored by the create
# endpoint. Everything NOT in this list is passed through unchanged.
AGENT_POLICY_STRIP_FIELDS = {
    "version", "created_at", "package_policies", "agents", "status",
    "revision", "updated_at", "updated_by", "has_agent_version_conditions",
    "package_agent_version_conditions", "unprivileged_agents",
    "fips_agents", "agents_per_version", "schema_version",
}

# Same idea, for each nested package_policy (integration) object.
# policy_id and policy_ids are CRITICAL to strip -- confirmed the
# hard way: leaving them in place means every created integration
# attaches to whatever policy ID the CAPTURE happened to record,
# ignoring the actual agent policy just created. During testing this
# silently attached test integrations to the real, live
# linux-workstation-policy instead of the intended test policy.
PACKAGE_POLICY_STRIP_FIELDS = {
    "id", "version", "revision", "created_at", "created_by",
    "updated_at", "updated_by", "policy_id", "policy_ids",
}


def curl_json(method, path, data=None):
    cmd = ["curl", "-s", "-u", f"elastic:{ELASTIC_PASSWORD}",
           "-H", "kbn-xsrf: true", "-H", "elastic-api-version: 2023-10-31",
           "-H", "Content-Type: application/json",
           "-X", method, f"{CALDERA_URL}{path}"]
    if data is not None:
        cmd += ["-d", json.dumps(data)]
    # List-form, no shell; method/path are always hardcoded literals
    # from this script's own calls, data comes from committed capture
    # files, never untrusted external input.
    result = subprocess.run(cmd, capture_output=True, text=True)  # noqa: S603
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        print(
            f"ERROR: non-JSON response from {method} {path}: "
            f"{result.stdout[:500]}",
            file=sys.stderr,
        )
        return None


def policy_exists(policy_id):
    resp = curl_json("GET", f"/api/fleet/agent_policies/{policy_id}")
    return resp is not None and "item" in resp


def strip_fields(d, strip_set):
    return {k: v for k, v in d.items() if k not in strip_set}


def provision_policy(capture_file):
    with open(capture_file) as f:
        captured = json.load(f)

    item = captured["item"]
    policy_id = item["id"]

    print(f"Checking policy: {policy_id}")
    if policy_exists(policy_id):
        print("  Already present -- skipping.")
        return

    print("  Missing -- creating.")
    package_policies = item.get("package_policies", [])
    agent_policy_body = strip_fields(item, AGENT_POLICY_STRIP_FIELDS)

    resp = curl_json("POST", "/api/fleet/agent_policies", agent_policy_body)
    if resp is None or "item" not in resp:
        print(
            f"  ERROR: failed to create agent policy {policy_id}: {resp}",
            file=sys.stderr,
        )
        return
    real_policy_id = resp["item"]["id"]
    print(f"  Agent policy created: {real_policy_id}")

    for pp in package_policies:
        pp_body = strip_fields(pp, PACKAGE_POLICY_STRIP_FIELDS)
        # Bind to the REAL, confirmed ID from the response above --
        # never assumed to match the pre-creation capture value, and
        # never inherited from the old capture's own policy_id.
        pp_body["policy_id"] = real_policy_id
        pp_body["policy_ids"] = [real_policy_id]
        pp_resp = curl_json("POST", "/api/fleet/package_policies", pp_body)
        if pp_resp is None or "item" not in pp_resp:
            print(
                f"  ERROR: failed to create package policy "
                f"{pp.get('name')}: {pp_resp}",
                file=sys.stderr,
            )
            continue
        pkg_name = pp.get("package", {}).get("name")
        print(f"  Package policy created: {pp.get('name')} ({pkg_name})")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(
        description="Stateless Fleet agent policy provisioning."
    )
    parser.add_argument(
        "--capture-dir", default=CAPTURE_DIR,
        help="Directory of captured policy JSON files "
             "(default: fleet-policy-captures/ next to this script)",
    )
    args = parser.parse_args()

    ELASTIC_PASSWORD = os.environ.get("ELASTIC_PASSWORD")
    if not ELASTIC_PASSWORD:
        print("ERROR: ELASTIC_PASSWORD environment variable not set.", file=sys.stderr)
        sys.exit(1)

    if not os.path.isdir(args.capture_dir):
        print(
            f"ERROR: capture directory not found: {args.capture_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    capture_files = sorted(
        os.path.join(args.capture_dir, f)
        for f in os.listdir(args.capture_dir)
        if f.endswith(".json")
    )

    if not capture_files:
        print(f"WARNING: no .json capture files found in {args.capture_dir}")
        sys.exit(0)

    # fleet-server-policy must exist before the other two can be
    # created successfully -- other policies may reference it or
    # depend on Fleet's own setup being complete. Process it first if
    # present, matching the real dependency order.
    capture_files.sort(key=lambda f: 0 if "fleet-server-policy" in f else 1)

    for f in capture_files:
        provision_policy(f)

    print("\nFleet policy provisioning complete.")
