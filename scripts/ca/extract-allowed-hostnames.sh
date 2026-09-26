#!/usr/bin/env bash
# extract-allowed-hostnames.sh
#
# Extracts real instance hostnames directly from committed Terraform
# source (never from live infrastructure state) and writes them to a
# JSON Lines allowlist that sign-server.py reads on every request.
# Deliberately hostname-only, never IP addresses -- a hostname exists
# the moment it's declared in a .tf file, before terraform apply ever
# runs, which lets this file be updated and pushed BEFORE a new
# instance is created. That ordering eliminates the sequencing gap
# where a freshly-booted node's first cert requests would otherwise
# be rejected while control-node still has the old list.
#
# Two categories of entry, both by design:
#   1. Every *-target.tf file, discovered dynamically -- a new target
#      is picked up automatically, no edit to this script required.
#   2. control-node.tf itself, extracted explicitly and separately --
#      handled as its own case, not swept in by the *-target.tf glob,
#      since it's a fundamentally different kind of entry: the CA's
#      own host, not a dynamically-added external target.
#
# Extraction is scoped to the google_compute_instance block
# specifically, not the whole file -- control-node.tf also declares
# a google_compute_address resource with its own "name" field, and a
# whole-file scan can't tell the two apart. Walks brace depth
# character by character to find the instance block's real end,
# rather than a naive regex, since a naive approach would also be
# fooled by nested blocks like network_interface { ... } inside the
# instance resource itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="$REPO_ROOT/ca/allowed-hostnames.jsonl"

mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "Extracting instance hostnames from committed Terraform source..."
true > "$OUTPUT_FILE"

extract_and_append() {
  local tf_file="$1"

  local hostname
  hostname=$(python3 -c "
import re, sys

with open('$tf_file') as f:
    content = f.read()

instance_match = re.search(r'resource\s+\"google_compute_instance\"[^{]*\{', content)
if not instance_match:
    print(f'ERROR: no google_compute_instance resource found in $tf_file', file=sys.stderr)
    sys.exit(1)

start = instance_match.end()
depth = 1
i = start
while depth > 0:
    if i >= len(content):
        print(f'ERROR: unbalanced braces in $tf_file', file=sys.stderr)
        sys.exit(1)
    if content[i] == '{':
        depth += 1
    elif content[i] == '}':
        depth -= 1
    i += 1
instance_block = content[start:i]

matches = re.findall(r'^\s*name\s*=\s*\"([^\"]+)\"', instance_block, re.MULTILINE)
if len(matches) != 1:
    print(f'ERROR: expected exactly 1 name match in the google_compute_instance block of $tf_file, found {len(matches)}: {matches}', file=sys.stderr)
    sys.exit(1)
print(matches[0])
")

  echo "  Found: $hostname (from $(basename "$tf_file"))"
  python3 -c "
import json
entry = {'hostname': '$hostname.internal', 'source_file': '$(basename "$tf_file")'}
print(json.dumps(entry))
" >> "$OUTPUT_FILE"
}

# Category 1: every dynamically-discovered target
shopt -s nullglob
TARGET_FILES=("$REPO_ROOT"/terraform/*-target.tf)
shopt -u nullglob

if [ ${#TARGET_FILES[@]} -eq 0 ]; then
  echo "WARNING: no *-target.tf files found in $REPO_ROOT/terraform/"
fi

for tf_file in "${TARGET_FILES[@]}"; do
  extract_and_append "$tf_file"
done

# Category 2: control-node itself, explicit and separate
CONTROL_NODE_FILE="$REPO_ROOT/terraform/control-node.tf"
if [ -f "$CONTROL_NODE_FILE" ]; then
  extract_and_append "$CONTROL_NODE_FILE"
else
  echo "WARNING: $CONTROL_NODE_FILE not found -- control-node's own hostname was not added."
fi

echo ""
echo "Wrote $(wc -l < "$OUTPUT_FILE" | tr -d ' ') hostname(s) to $OUTPUT_FILE"
echo "Remember: commit and push this file, then confirm control-node has"
echo "pulled it, BEFORE running terraform apply for any new instance."
