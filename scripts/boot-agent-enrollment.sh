#!/usr/bin/env bash
# boot-agent-enrollment.sh
#
# Runs once at instance boot (as a GCE Linux startup script) on Ubuntu
# workstation targets. Enrolls the Elastic Agent binary already baked
# into the golden image (see packer/ubuntu-workstation) against Fleet
# Server, using values supplied at instance-creation time via GCE
# metadata -- never baked into the image itself.
#
# Mirrors the reasoning in the Windows equivalent
# (boot-agent-enrollment.ps1, drafted earlier): the agent binary is
# static and belongs in the image; the Fleet URL and enrollment token
# are session-specific and belong at boot time.
#
# Required instance metadata keys (set via Terraform when the VM is
# created, NOT baked into the image):
#   fleet-url                 e.g. https://10.60.10.39:8220
#   fleet-enrollment-token
#
# CALDERA enrollment is deliberately not handled here -- same reasoning
# as the Windows script: Sandcat's dropper is generated live by a
# running CALDERA server, not a static binary, so there's nothing to
# stage ahead of time. That piece gets added once the demo controller
# or a manual test actually triggers it.

set -euo pipefail

LOG_FILE="/var/log/boot-agent-enrollment.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- Boot agent enrollment starting: $(date -u +%FT%TZ) ---"

get_metadata() {
  local key="$1"
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}" \
    || echo ""
}

FLEET_URL=$(get_metadata "fleet-url")
FLEET_ENROLLMENT_TOKEN=$(get_metadata "fleet-enrollment-token")

AGENT_BIN="/opt/elastic/elastic-agent/elastic-agent"

if [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
  echo "Skipping Elastic Agent enrollment: fleet-url or fleet-enrollment-token metadata not set."
  exit 0
fi

if [ ! -x "$AGENT_BIN" ]; then
  echo "ERROR: Elastic Agent binary not found at $AGENT_BIN. Was it baked into this image?"
  exit 1
fi

# Already enrolled from a previous boot (e.g. instance stop/start, not a
# fresh disk) -- don't re-enroll, which would create a duplicate agent
# record in Fleet.
if "$AGENT_BIN" status >/dev/null 2>&1; then
  echo "Elastic Agent already installed and running. Skipping enrollment."
  exit 0
fi

echo "Enrolling Elastic Agent with Fleet at $FLEET_URL ..."

# Wait for Fleet Server to actually be reachable before attempting
# enrollment. This directly addresses a real failure hit on 2026-09-02:
# control-node (and therefore Fleet Server) is deliberately stopped
# between sessions to save cost, and a workstation target booting
# before control-node has finished its own startup previously produced
# a hard, unrecoverable enrollment failure with no retry -- requiring
# a manual re-run. Bounded retries with backoff here means a normal
# timing mismatch resolves on its own instead of needing intervention.
FLEET_HOST=$(echo "$FLEET_URL" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')
FLEET_PORT=$(echo "$FLEET_URL" | sed -E 's#^.*:([0-9]+).*$#\1#')

echo "Waiting for Fleet Server at ${FLEET_HOST}:${FLEET_PORT} to become reachable..."
FLEET_REACHABLE=0
for i in $(seq 1 20); do
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${FLEET_HOST}/${FLEET_PORT}" 2>/dev/null; then
    FLEET_REACHABLE=1
    echo "Fleet Server reachable after $((i - 1)) retries."
    break
  fi
  echo "  Fleet Server not reachable yet (attempt $i/20), waiting 15s..."
  sleep 15
done

if [ "$FLEET_REACHABLE" -ne 1 ]; then
  echo "ERROR: Fleet Server at ${FLEET_HOST}:${FLEET_PORT} was not reachable after 20 attempts (~5 minutes)."
  echo "control-node may not be running. Enrollment not attempted -- rerun this script manually once control-node is confirmed up:"
  echo "  sudo bash /var/lib/google/startup-script"
  exit 1
fi

# --insecure: Fleet Server's own listener uses a self-signed cert (same
# posture as every local/dev enrollment so far in this project). Not
# appropriate once this moves toward the real public-facing demo -- see
# docs/09-public-tls-and-domain.md.
"$AGENT_BIN" install \
  --url="$FLEET_URL" \
  --enrollment-token="$FLEET_ENROLLMENT_TOKEN" \
  --insecure \
  --non-interactive \
  --force

echo "--- Boot agent enrollment finished: $(date -u +%FT%TZ) ---"
