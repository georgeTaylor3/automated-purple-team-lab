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
