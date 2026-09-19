#!/usr/bin/env bash
# personal-info-check.sh
#
# Checks staged files for personal identifiers. Username and current
# hostname are computed dynamically at scan time -- never stored as
# literal strings, so this script itself contains no personal data
# and is fully safe to commit. Only genuinely non-derivable
# identifiers (email, surname, any retired/historical hostname) live
# in local-patterns.gitignored, kept as small as possible.

set -euo pipefail

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)
if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PATTERNS_FILE="$SCRIPT_DIR/local-patterns.gitignored"

# Computed fresh every run -- never hardcoded, never stored.
GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
DYNAMIC_PATTERNS=("$USER" "$(hostname)")
if [ -n "$GCLOUD_ACCOUNT" ]; then
  DYNAMIC_PATTERNS+=("$GCLOUD_ACCOUNT")
fi

FOUND=0

print_indented() {
  local text="$1"
  while IFS= read -r line; do
    echo "    $line"
  done <<< "$text"
}

for pattern in "${DYNAMIC_PATTERNS[@]}"; do
  if [ -n "$pattern" ]; then
    matches=$(echo "$STAGED_FILES" | xargs -r grep -lF -- "$pattern" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      echo "  Found '$pattern' (dynamic) in:"
      print_indented "$matches"
      FOUND=1
    fi
  fi
done

if [ -f "$LOCAL_PATTERNS_FILE" ]; then
  # Strip blank lines and comments before use -- an unfiltered blank
  # line, given to grep -f as a pattern, matches every line in every
  # file (an empty string is trivially a substring of anything). This
  # is a real bug the old script had silently the whole time.
  REAL_PATTERNS=$(grep -v '^\s*#' "$LOCAL_PATTERNS_FILE" | grep -v '^\s*$' || true)
  if [ -n "$REAL_PATTERNS" ]; then
    matches=$(echo "$STAGED_FILES" | xargs -r grep -lF -f <(echo "$REAL_PATTERNS") 2>/dev/null || true)
    if [ -n "$matches" ]; then
      echo "  Found local pattern match in:"
      print_indented "$matches"
      FOUND=1
    fi
  fi
fi

if [ "$FOUND" -eq 1 ]; then
  exit 1
fi

exit 0
