#!/usr/bin/env bash
# scripts/audit-rbac.sh
#
# Generates a full RBAC audit snapshot of the project: every service
# account (discovered dynamically, not hardcoded), every custom IAM role,
# every secret and who can read it, and the raw project IAM policy as a
# catch-all (catches human accounts and anything the per-service-account
# loop below wouldn't otherwise surface).
#
# Run this, then diff the output against docs/10-rbac-matrix.md. Anything
# in the audit output that isn't in the doc is undocumented and worth
# investigating. Anything in the doc that isn't in the audit output is
# stale and should be removed from the doc.
#
# Usage: ./scripts/audit-rbac.sh
# Writes a timestamped markdown file to the current directory.

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_FILE="rbac-audit-${TIMESTAMP}.md"

echo "Auditing project: $PROJECT_ID"
echo "Writing to: $OUTPUT_FILE"
echo

{
  echo "# RBAC Audit -- $PROJECT_ID"
  echo
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "Compare this against docs/10-rbac-matrix.md. Anything here not in"
  echo "that doc is undocumented. Anything in that doc not here is stale."
  echo
  echo "---"
  echo
} > "$OUTPUT_FILE"

# -----------------------------------------------------------------------
# Section 1: full raw project IAM policy
#
# Catches everything -- human accounts, service accounts, anything with
# any binding at all. This is the ground truth; everything below is just
# the same data reorganized for readability.
# -----------------------------------------------------------------------
{
  echo "## Full project IAM policy (raw)"
  echo
  echo '```'
  gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten="bindings[].members" \
    --format="table(bindings.members,bindings.role,bindings.condition.title,bindings.condition.expression)"
  echo '```'
  echo
} >> "$OUTPUT_FILE"

# -----------------------------------------------------------------------
# Section 2: service account inventory + per-account bindings
#
# Discovered dynamically -- this list is never hardcoded, so a service
# account created since the last audit still shows up here automatically.
# -----------------------------------------------------------------------
{
  echo "## Service accounts"
  echo
  echo "### Inventory"
  echo
  echo '```'
  gcloud iam service-accounts list --project="$PROJECT_ID" \
    --format="table(email,displayName,disabled)"
  echo '```'
  echo
} >> "$OUTPUT_FILE"

SA_LIST=$(gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)")

for SA in $SA_LIST; do
  {
    echo "### $SA"
    echo
    echo '```'
    gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:${SA}" \
      --format="table(bindings.role,bindings.condition.title,bindings.condition.expression)"
    echo '```'
    echo
  } >> "$OUTPUT_FILE"
done

# -----------------------------------------------------------------------
# Section 3: custom IAM roles, full permission lists
#
# Also discovered dynamically, not a hardcoded list of role names.
# -----------------------------------------------------------------------
{
  echo "## Custom IAM roles"
  echo
} >> "$OUTPUT_FILE"

CUSTOM_ROLES=$(gcloud iam roles list --project="$PROJECT_ID" --format="value(name)")

if [ -z "$CUSTOM_ROLES" ]; then
  echo "(no custom roles found)" >> "$OUTPUT_FILE"
else
  for ROLE in $CUSTOM_ROLES; do
    ROLE_ID=$(basename "$ROLE")
    {
      echo "### $ROLE_ID"
      echo
      echo '```'
      gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" \
        --format="yaml(title,description,stage,includedPermissions)"
      echo '```'
      echo
    } >> "$OUTPUT_FILE"
  done
fi

# -----------------------------------------------------------------------
# Section 4: every secret and who can read it
#
# Also discovered dynamically.
# -----------------------------------------------------------------------
{
  echo "## Secret Manager"
  echo
} >> "$OUTPUT_FILE"

SECRETS=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)")

if [ -z "$SECRETS" ]; then
  echo "(no secrets found)" >> "$OUTPUT_FILE"
else
  for SECRET in $SECRETS; do
    {
      echo "### $SECRET"
      echo
      echo '```'
      gcloud secrets get-iam-policy "$SECRET" --project="$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="table(bindings.role,bindings.members)" 2>/dev/null \
        || echo "(no IAM bindings on this secret)"
      echo '```'
      echo
    } >> "$OUTPUT_FILE"
  done
fi

echo "Done. Audit written to $OUTPUT_FILE"
echo "Diff it against docs/10-rbac-matrix.md and update either the doc or the live project as needed."
