#!/usr/bin/env bash
# check-live-secrets.sh
#
# Dynamically discovers every secret in the project and checks every
# non-destroyed version of each (not just the latest) against staged
# changes. Catches opaque, randomly-generated credentials no regex
# pattern could ever distinguish from ordinary text -- including old,
# rotated-out values that could still be sitting in a script from
# before a rotation.
#
# Deliberately broader access than everything else in this project:
# every other credential grant here is scoped to one specific secret
# for one specific service account. This script needs list+read
# across ALL secrets to discover them dynamically. Fine for your own
# already-broadly-privileged local account; would need real
# reconsideration if ever run by anything less privileged.
#
# Slower than a fixed secret list, by design -- N secrets x M
# versions each is a real number of gcloud calls per commit.
#
# Fails partially closed: if gcloud/Secret Manager access isn't
# available at all, prompts for explicit confirmation.
#
# To skip the prompt for exactly ONE commit when you know you're
# offline:
#   touch /tmp/.purple-lab-skip-live-secret-check
#
# Self-deleting marker, not an environment variable -- a subprocess
# script cannot reach back and unset an env var in your shell, so an
# env-var bypass could silently persist across multiple commits if
# forgotten. A self-deleting file cannot make that mistake.
#
# On a FAIL, the matched line is shown with the actual secret value
# redacted (***) -- context without echoing the real credential.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

STATUS_WIDTH=74

print_status_line() {
  local name="$1"
  local status="$2"
  local color="$3"
  local dots_needed=$((STATUS_WIDTH - ${#name} - ${#status}))
  local dots=""
  if [ "$dots_needed" -gt 0 ]; then
    dots=$(printf '%*s' "$dots_needed" '' | tr ' ' '.')
  fi
  printf "  %s%s${color}%s${NC}\n" "$name" "$dots" "$status"
}

SKIP_MARKER="/tmp/.purple-lab-skip-live-secret-check"
SKIP_LIVE_CHECK=0

if [ -f "$SKIP_MARKER" ]; then
  SKIP_LIVE_CHECK=1
  rm -f "$SKIP_MARKER"
fi

prompt_to_continue() {
  if [ "$SKIP_LIVE_CHECK" -eq 1 ]; then
    echo "  WARNING: one-time skip marker consumed -- proceeding without checking live GCP secrets."
    echo "  This bypass does NOT apply to future commits -- the marker has been removed."
    return 0
  fi

  while true; do
    read -r -p "Continue without checking live GCP secrets? (type 'yes' to continue): " answer
    if [ "$answer" == "yes" ]; then
      return 0
    elif [ "$answer" == "no" ]; then
      echo "  Commit blocked."
      exit 1
    else
      echo "  Please type exactly 'yes' or 'no'."
    fi
  done
}

CURRENT_BRANCH=$(git branch --show-current)
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)
if [ -z "$STAGED_FILES" ]; then
  echo "  No staged changes in branch: $CURRENT_BRANCH; project: $REPO_NAME"
  exit 0
fi

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")

if [ -z "$PROJECT_ID" ]; then
  echo "  WARNING: no gcloud project set -- live secret values cannot be checked."
  prompt_to_continue
  exit 0
fi

mapfile -t SECRET_NAMES < <(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null)

if [ "${#SECRET_NAMES[@]}" -eq 0 ]; then
  echo "  WARNING: no secrets found in Secret Manager (or list failed)."
  prompt_to_continue
  exit 0
fi

echo "  Secrets fetched -- checking for secrets in branch: $CURRENT_BRANCH; project: $REPO_NAME"
echo "  (${#SECRET_NAMES[@]} secrets discovered, checking all non-destroyed versions of each)"
echo

FOUND_LEAK=0
ANY_SECRET_LOADED=0

for secret_name in "${SECRET_NAMES[@]}"; do
  mapfile -t VERSIONS < <(gcloud secrets versions list "$secret_name" --project="$PROJECT_ID" --format="value(name)" --filter="state!=DESTROYED" 2>/dev/null)

  if [ "${#VERSIONS[@]}" -eq 0 ]; then
    print_status_line "$secret_name" "SKIP (no accessible versions)" "$RED"
    continue
  fi

  SECRET_MATCHES=""
  SECRET_HAD_VALUE=0

  for version in "${VERSIONS[@]}"; do
    secret_value=$(gcloud secrets versions access "$version" --secret="$secret_name" --project="$PROJECT_ID" 2>/dev/null || echo "")
    if [ -z "$secret_value" ]; then
      continue
    fi
    SECRET_HAD_VALUE=1
    ANY_SECRET_LOADED=1

    for f in $STAGED_FILES; do
      if [ -f "$f" ]; then
        while IFS=: read -r line_num line_content; do
          redacted="${line_content//$secret_value/***}"
          SECRET_MATCHES="${SECRET_MATCHES}      $f:$line_num (version $version): $redacted"$'\n'
        done < <(grep -Fn -- "$secret_value" "$f" 2>/dev/null || true)
      fi
    done
  done

  if [ -n "$SECRET_MATCHES" ]; then
    print_status_line "$secret_name" "FAIL" "$RED"
    printf "%s" "$SECRET_MATCHES"
    FOUND_LEAK=1
  elif [ "$SECRET_HAD_VALUE" -eq 1 ]; then
    print_status_line "$secret_name" "PASS" "$GREEN"
  else
    print_status_line "$secret_name" "SKIP (not accessible)" "$RED"
  fi
done

echo

if [ "$ANY_SECRET_LOADED" -eq 0 ]; then
  echo "  WARNING: no secret values could be retrieved -- live-value check did not run."
  prompt_to_continue
fi

if [ "$FOUND_LEAK" -eq 1 ]; then
  echo "  Live secret(s) detected in staged changes -- commit blocked."
  exit 1
fi

exit 0
