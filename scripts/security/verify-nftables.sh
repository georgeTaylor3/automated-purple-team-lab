#!/usr/bin/env bash
# verify-nftables.sh
#
# Applies control-node's host-based nftables ruleset safely:
#   1. Syntax-check the config before ever loading it.
#   2. Apply it.
#   3. Confirm the ACTUAL, LOADED ruleset (not just the source file)
#      genuinely contains a correct SSH rule for the real IAP range.
#   4. If that confirmation fails for any reason, immediately flush
#      our own table (inet filter) back to empty rather than leave a
#      broken SSH rule in place -- scoped to this table alone, never
#      a bare "flush ruleset", which would also wipe Docker's own
#      separate nftables tables. "No host firewall" is a known, safe,
#      recoverable state (the separate VPC firewall layer still
#      applies); "a host firewall missing its SSH rule" is the one
#      genuinely unrecoverable state without GCP's Serial Console.
#
# This script's own exit code is always 0 (non-fatal to the caller),
# matching this project's existing pattern for boot-time steps that
# shouldn't block the rest of the deploy if they fail -- but it
# prints clearly whether the firewall ended up applied or reverted,
# so a failure is visible, not silent.
#
# Designed to be callable both from control-node's own boot sequence
# and, later, from a CI/CD post-deploy health check -- the same
# verification logic either way.

set -uo pipefail
# Deliberately not set -e: every failure path here needs to reach the
# flush-to-safe step, not abort partway through.

CONFIG_FILE="${1:-/opt/purple-lab/scripts/security/control-node-nftables.conf}"
EXPECTED_SSH_RANGE="35.235.240.0/20"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "WARNING: nftables config not found at $CONFIG_FILE -- skipping, no ruleset applied."
  exit 0
fi

echo "Checking nftables config syntax..."
if ! sudo nft -c -f "$CONFIG_FILE" 2>/tmp/nft-check-error.log; then
  echo "WARNING: nftables config failed syntax check -- not applied."
  cat /tmp/nft-check-error.log
  exit 0
fi

echo "Syntax OK. Applying..."
sudo nft -f "$CONFIG_FILE"

echo "Verifying the LOADED ruleset's SSH rule, not just the source file..."
LOADED_SSH_RULE=$(sudo nft list ruleset | grep "dport 22" || true)

if echo "$LOADED_SSH_RULE" | grep -q "$EXPECTED_SSH_RANGE"; then
  echo "Verified: SSH rule present and correctly scoped to $EXPECTED_SSH_RANGE."
  echo "Host firewall applied successfully."
else
  echo "WARNING: loaded ruleset's SSH rule is missing or incorrect."
  echo "  Found: ${LOADED_SSH_RULE:-<no SSH rule found at all>}"
  echo "Flushing our own table back to empty (safe, recoverable state) rather than leaving this in place."
  # Scoped to inet filter alone -- the config file was already loaded
  # successfully moments ago (we're past step 2), so this table
  # definitely exists at this point. A bare 'nft flush ruleset' here
  # would hit the same Docker-breaking bug the config file itself was
  # fixed for -- never use it.
  sudo nft flush table inet filter
  echo "Table flushed. Host firewall NOT applied this boot -- fix scripts/security/control-node-nftables.conf and redeploy."
fi

exit 0
