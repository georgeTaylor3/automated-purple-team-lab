#!/usr/bin/env bash
# scripts/rbac-diff.sh
#
# Compares the CURRENT live IAM/secrets/custom-role state against the
# reviewed baseline (docs/rbac-baseline.json, created by
# scripts/rbac-baseline.sh). Prints only the deltas:
#
#   + ADDED    -- present live but not in the baseline. Possible scope
#                 creep: something got more access than was approved.
#   - REMOVED  -- present in the baseline but not live. Something got
#                 revoked or drifted since the baseline was captured.
#   ! UNDOCUMENTED SERVICE ACCOUNT -- exists live, isn't in the baseline
#                 at all (not even with zero roles).
#
# Safe to run as often as you like -- this is read-only, it never
# modifies the baseline or the live project.

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
BASELINE="docs/rbac-baseline.json"

if [ ! -f "$BASELINE" ]; then
  echo "No baseline found at $BASELINE."
  echo "Run scripts/rbac-baseline.sh first to establish one."
  exit 1
fi

# -----------------------------------------------------------------------
# Verify non-repudiation before trusting this baseline at all. An
# unsigned or tampered baseline is not a trustworthy "should be" -- it
# could have been hand-edited by anyone with repo write access, not just
# the person who reviewed and approved the actual live state.
# -----------------------------------------------------------------------
SIGN_FORMAT=$(git config --get gpg.format || echo "openpgp")

if [ "$SIGN_FORMAT" = "ssh" ]; then
  SIG_FILE="${BASELINE}.sig"
else
  SIG_FILE="${BASELINE}.asc"
fi

if [ ! -f "$SIG_FILE" ]; then
  echo "ERROR: $SIG_FILE not found. This baseline is unsigned."
  echo "An unsigned baseline provides no non-repudiation -- refusing to"
  echo "diff against it. Re-run scripts/rbac-baseline.sh to produce a"
  echo "signed baseline."
  exit 1
fi

echo "Verifying baseline signature ($SIGN_FORMAT format)..."

if [ "$SIGN_FORMAT" = "ssh" ]; then
  ALLOWED_SIGNERS=$(git config --get gpg.ssh.allowedSignersFile || true)
  if [ -z "$ALLOWED_SIGNERS" ] || [ ! -f "$ALLOWED_SIGNERS" ]; then
    echo "ERROR: no gpg.ssh.allowedSignersFile configured, or the file"
    echo "doesn't exist. SSH signature verification needs this to map"
    echo "your identity to your public key. See:"
    echo "  https://docs.github.com/en/authentication/managing-commit-signature-verification/using-ssh-key-signatures"
    exit 1
  fi

  IDENTITY=$(git config --get user.email)
  if ! ssh-keygen -Y verify -f "$ALLOWED_SIGNERS" -I "$IDENTITY" -n rbac-baseline -s "$SIG_FILE" < "$BASELINE"; then
    echo
    echo "ERROR: baseline signature verification FAILED."
    echo "The baseline file may have been altered since it was signed, or"
    echo "signed by an untrusted key. Refusing to diff against it."
    exit 1
  fi
else
  if ! gpg --verify "$SIG_FILE" "$BASELINE" 2>&1; then
    echo
    echo "ERROR: baseline signature verification FAILED."
    echo "The baseline file may have been altered since it was signed, or"
    echo "signed by an untrusted key. Refusing to diff against it."
    exit 1
  fi
fi
echo "Signature valid."
echo

echo "Comparing live state against baseline from $(jq -r '.generated' "$BASELINE")..."
echo

DRIFT_FOUND=0

# -----------------------------------------------------------------------
# Service accounts
# -----------------------------------------------------------------------
SA_LIST=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)")

for SA in $SA_LIST; do
  LIVE=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:${SA}" \
    --format="json(bindings.role,bindings.condition.title)" | \
    jq -c '[.[] | if .bindings.condition.title then "\(.bindings.role) [\(.bindings.condition.title)]" else .bindings.role end] | sort')

  BASE=$(jq -c --arg sa "$SA" '.service_accounts[$sa] // [] | sort' "$BASELINE")

  ADDED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$live - $base')
  REMOVED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$base - $live')

  if [ "$ADDED" != "[]" ] || [ "$REMOVED" != "[]" ]; then
    DRIFT_FOUND=1
    echo "=== $SA ==="
    if [ "$ADDED" != "[]" ]; then
      echo "  + ADDED (not in baseline -- possible scope creep):"
      echo "$ADDED" | jq -r '.[] | "      + \(.)"'
    fi
    if [ "$REMOVED" != "[]" ]; then
      echo "  - REMOVED (in baseline but not live -- revoked or drifted):"
      echo "$REMOVED" | jq -r '.[] | "      - \(.)"'
    fi
    echo
  fi
done

BASELINE_SAS=$(jq -r '.service_accounts | keys[]' "$BASELINE")
for SA in $SA_LIST; do
  if ! echo "$BASELINE_SAS" | grep -qx "$SA"; then
    DRIFT_FOUND=1
    echo "=== $SA ==="
    echo "  ! UNDOCUMENTED SERVICE ACCOUNT -- not in baseline at all"
    echo
  fi
done

# -----------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------
SECRETS=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)")

for SECRET in $SECRETS; do
  LIVE=$(gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT_ID" \
    --format="json(bindings.members)" 2>/dev/null | \
    jq -c '[.[].bindings.members[]?] | flatten | unique | sort' 2>/dev/null || echo "[]")
  BASE=$(jq -c --arg s "$SECRET" '.secrets[$s] // [] | sort' "$BASELINE")

  ADDED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$live - $base')
  REMOVED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$base - $live')

  if [ "$ADDED" != "[]" ] || [ "$REMOVED" != "[]" ]; then
    DRIFT_FOUND=1
    echo "=== secret: $SECRET ==="
    if [ "$ADDED" != "[]" ]; then
      echo "  + ADDED access:"
      echo "$ADDED" | jq -r '.[] | "      + \(.)"'
    fi
    if [ "$REMOVED" != "[]" ]; then
      echo "  - REMOVED access:"
      echo "$REMOVED" | jq -r '.[] | "      - \(.)"'
    fi
    echo
  fi
done

# -----------------------------------------------------------------------
# Custom role permissions
# -----------------------------------------------------------------------
CUSTOM_ROLES=$(gcloud iam roles list --project="$PROJECT_ID" --format="value(name)")

for ROLE in $CUSTOM_ROLES; do
  ROLE_ID=$(basename "$ROLE")
  LIVE=$(gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" \
    --format="json(includedPermissions)" | jq -c '.includedPermissions // [] | sort')
  BASE=$(jq -c --arg r "$ROLE_ID" '.custom_roles[$r] // [] | sort' "$BASELINE")

  ADDED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$live - $base')
  REMOVED=$(jq -n --argjson live "$LIVE" --argjson base "$BASE" '$base - $live')

  if [ "$ADDED" != "[]" ] || [ "$REMOVED" != "[]" ]; then
    DRIFT_FOUND=1
    echo "=== custom role: $ROLE_ID ==="
    if [ "$ADDED" != "[]" ]; then
      echo "  + ADDED permissions:"
      echo "$ADDED" | jq -r '.[] | "      + \(.)"'
    fi
    if [ "$REMOVED" != "[]" ]; then
      echo "  - REMOVED permissions:"
      echo "$REMOVED" | jq -r '.[] | "      - \(.)"'
    fi
    echo
  fi
done

if [ "$DRIFT_FOUND" -eq 0 ]; then
  echo "No drift detected. Live state matches the baseline exactly."
else
  echo "Drift detected above. For each item:"
  echo "  - If intentional and reviewed: run scripts/rbac-baseline.sh to update the baseline."
  echo "  - If not: investigate why the live project doesn't match what was approved."
fi
