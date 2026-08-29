#!/usr/bin/env bash
# scripts/rbac-baseline.sh
#
# Captures the CURRENT live IAM/secrets/custom-role state as the reviewed
# "should be" baseline (docs/rbac-baseline.json). This is the source of
# truth scripts/rbac-diff.sh compares against.
#
# Run this deliberately, only after you've reviewed the current state and
# consider it correct -- e.g. right after applying a Terraform change you
# just checked, not routinely. Every time this runs, it overwrites the
# previous baseline: whatever is live right now becomes "approved."
#
# Everything is discovered dynamically (service accounts, secrets, custom
# roles) -- nothing is hardcoded, so a newly created account or secret
# gets captured automatically the next time this runs.

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
OUT="docs/rbac-baseline.json"

echo "This captures the CURRENT live state as the reviewed baseline."
echo "Only do this after you've deliberately reviewed the current state."
read -r -p "Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

echo "Capturing service account bindings..."
SA_LIST=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)")

SA_JSON="{}"
for SA in $SA_LIST; do
  BINDINGS=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:${SA}" \
    --format="json(bindings.role,bindings.condition.title)" | \
    jq -c '[.[] | if .bindings.condition.title then "\(.bindings.role) [\(.bindings.condition.title)]" else .bindings.role end] | sort')
  SA_JSON=$(echo "$SA_JSON" | jq --arg sa "$SA" --argjson b "$BINDINGS" '. + {($sa): $b}')
done

echo "Capturing secret access..."
SECRETS=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)")

SECRETS_JSON="{}"
for SECRET in $SECRETS; do
  MEMBERS=$(gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT_ID" \
    --format="json(bindings.members)" 2>/dev/null | \
    jq -c '[.[].bindings.members[]?] | flatten | unique | sort' 2>/dev/null || echo "[]")
  SECRETS_JSON=$(echo "$SECRETS_JSON" | jq --arg s "$SECRET" --argjson m "$MEMBERS" '. + {($s): $m}')
done

echo "Capturing custom role permissions..."
CUSTOM_ROLES=$(gcloud iam roles list --project="$PROJECT_ID" --format="value(name)")

ROLES_JSON="{}"
for ROLE in $CUSTOM_ROLES; do
  ROLE_ID=$(basename "$ROLE")
  PERMS=$(gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" \
    --format="json(includedPermissions)" | jq -c '.includedPermissions // [] | sort')
  ROLES_JSON=$(echo "$ROLES_JSON" | jq --arg r "$ROLE_ID" --argjson p "$PERMS" '. + {($r): $p}')
done

jq -n \
  --arg generated "$(date -u +%FT%TZ)" \
  --arg project "$PROJECT_ID" \
  --argjson sa "$SA_JSON" \
  --argjson secrets "$SECRETS_JSON" \
  --argjson roles "$ROLES_JSON" \
  '{generated: $generated, project_id: $project, service_accounts: $sa, secrets: $secrets, custom_roles: $roles}' \
  > "$OUT"

echo
echo "Baseline written to $OUT"

# -----------------------------------------------------------------------
# Non-repudiation: a detached signature over the baseline content. A
# hash alone only proves the file wasn't corrupted -- anyone could
# recompute a matching hash. A signature from a private key only the
# signer holds proves WHO approved this exact content, and the signer
# cannot credibly deny it. This uses the same YubiKey-backed key already
# configured for signed git commits (git config user.signingkey), not a
# separate key to manage.
# -----------------------------------------------------------------------
SIGNING_KEY=$(git config --get user.signingkey || true)
SIGN_FORMAT=$(git config --get gpg.format || echo "openpgp")

if [ -z "$SIGNING_KEY" ]; then
  echo
  echo "WARNING: no git signing key configured (git config user.signingkey)."
  echo "Baseline written WITHOUT a signature. Set up commit signing first,"
  echo "then rerun this script so the baseline can be signed."
  exit 0
fi

echo "Signing baseline (format: $SIGN_FORMAT) with key $SIGNING_KEY..."
echo "Touch your YubiKey if prompted."

if [ "$SIGN_FORMAT" = "ssh" ]; then
  # SSH-based signing (git config gpg.format ssh) -- uses the same
  # YubiKey-resident SSH key already configured for commit signing, via
  # OpenSSH's own detached signature format. ssh-keygen writes the
  # signature to "$OUT.sig" automatically.
  ssh-keygen -Y sign -f "$SIGNING_KEY" -n rbac-baseline "$OUT"
  SIG_FILE="${OUT}.sig"
else
  gpg --default-key "$SIGNING_KEY" --detach-sign --armor --output "${OUT}.asc" "$OUT"
  SIG_FILE="${OUT}.asc"
fi

echo
echo "Baseline signed: $SIG_FILE"
echo "Commit both $OUT and $SIG_FILE together."
echo "scripts/rbac-diff.sh will refuse to trust an unsigned or tampered baseline."
