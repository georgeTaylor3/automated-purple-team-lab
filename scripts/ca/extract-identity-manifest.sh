#!/usr/bin/env bash
# extract-identity-manifest.sh
#
# Generates a single, authoritative identity manifest -- every VM and
# every container in the lab, with its canonical identity string and
# its parent relationship -- satisfying NIST 800-53 CM-8 (System
# Component Inventory) and specifically CM-8(7) (Centralized
# Repository). Never hand-maintained: every entry is extracted from
# the real, existing authoritative source for that layer (Terraform
# for VMs, docker-compose.yml for containers), never declared here
# independently -- CM-8 explicitly requires avoiding "duplicate
# accounting of components," which a hand-maintained second copy of
# the same facts would violate the moment it drifted out of sync.
#
# This is the successor to extract-allowed-hostnames.sh -- VM
# extraction now uses python-hcl2, a real HCL2 parser, replacing an
# earlier hand-rolled brace-depth scanner. Container-layer extraction
# uses PyYAML, also a real parser, against docker-compose.yml.
#
# Neither layer uses text-pattern scanning. docker-compose.yml's
# volumes: section declares names (caldera-data, caldera-conf, etc.)
# at the exact same indentation level as services: does -- a naive
# text-level match cannot tell them apart, but a real parser
# understands they're genuinely different keys in the document
# structure. Terraform files can declare multiple resource types in
# one file (control-node.tf has both google_compute_address and
# google_compute_instance) -- a real parser distinguishes them by
# actual structure, not by counting characters.
#
# Note: python-hcl2 preserves literal quote characters in both parsed
# keys and values -- confirmed empirically against a real file before
# writing this. 'google_compute_instance' comes back as the literal
# string '"google_compute_instance"'; every comparison and extracted
# value below explicitly strips those quote characters.
#
# Requires: pyyaml, python-hcl2 (see scripts/ca/requirements.txt)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_FILE="$REPO_ROOT/ca/identity-manifest.jsonl"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "Generating identity manifest from committed source..."
true > "$OUTPUT_FILE"

extract_vm_and_append() {
  local tf_file="$1"

  local hostname
  hostname=$(python3 -c "
import hcl2, sys

with open('$tf_file') as f:
    parsed = hcl2.load(f)

# hcl2 preserves literal quote characters in both keys and values --
# confirmed empirically against a real file before trusting this.
# 'google_compute_instance' comes back as the literal string
# '\"google_compute_instance\"'; strip() removes those quote chars.
instance_entries = []
for resource_entry in parsed.get('resource', []):
    for resource_type, resources in resource_entry.items():
        if resource_type.strip('\"') == 'google_compute_instance':
            instance_entries.append(resources)

if len(instance_entries) != 1:
    print(f'ERROR: expected exactly 1 google_compute_instance resource in $tf_file, found {len(instance_entries)}', file=sys.stderr)
    sys.exit(1)

resources = instance_entries[0]
if len(resources) != 1:
    print(f'ERROR: expected exactly 1 named instance within the google_compute_instance block of $tf_file, found {len(resources)}', file=sys.stderr)
    sys.exit(1)

_, fields = next(iter(resources.items()))
name_value = fields.get('name')
if name_value is None:
    print(f'ERROR: google_compute_instance in $tf_file has no name field', file=sys.stderr)
    sys.exit(1)

print(name_value.strip('\"'))
")

  echo "  VM: $hostname.internal (from $(basename "$tf_file"))" >&2
  python3 -c "
import json
entry = {
    'identity': '$hostname.internal',
    'type': 'vm',
    'parent': None,
    'source_file': '$(basename "$tf_file")',
}
print(json.dumps(entry))
" >> "$OUTPUT_FILE"

  echo "$hostname.internal"
}

# --- VM layer ---
shopt -s nullglob
TARGET_FILES=("$REPO_ROOT"/terraform/*-target.tf)
shopt -u nullglob

if [ ${#TARGET_FILES[@]} -eq 0 ]; then
  echo "WARNING: no *-target.tf files found in $REPO_ROOT/terraform/"
fi

for tf_file in "${TARGET_FILES[@]}"; do
  extract_vm_and_append "$tf_file" > /dev/null
done

CONTROL_NODE_FILE="$REPO_ROOT/terraform/control-node.tf"
CONTROL_NODE_HOSTNAME=""
if [ -f "$CONTROL_NODE_FILE" ]; then
  CONTROL_NODE_HOSTNAME=$(extract_vm_and_append "$CONTROL_NODE_FILE")
else
  echo "WARNING: $CONTROL_NODE_FILE not found -- control-node's own hostname was not added, and no container-layer entries can be generated (they need a parent)."
fi

# --- Container layer ---
if [ -n "$CONTROL_NODE_HOSTNAME" ] && [ -f "$COMPOSE_FILE" ]; then
  python3 -c "
import yaml, json

with open('$COMPOSE_FILE') as f:
    compose = yaml.safe_load(f)

services = compose.get('services', {})
parent = '$CONTROL_NODE_HOSTNAME'

for service_name in services:
    identity = f'{service_name}.{parent}'
    entry = {
        'identity': identity,
        'type': 'container',
        'parent': parent,
        'source_file': 'docker-compose.yml',
    }
    print(f'  Container: {identity}')
    with open('$OUTPUT_FILE', 'a') as out:
        out.write(json.dumps(entry) + chr(10))
"
elif [ ! -f "$COMPOSE_FILE" ]; then
  echo "WARNING: $COMPOSE_FILE not found -- no container-layer entries generated."
fi

echo ""
echo "Wrote $(wc -l < "$OUTPUT_FILE" | tr -d ' ') identities to $OUTPUT_FILE"
echo "Remember: commit and push this file, then confirm control-node has"
echo "pulled it, BEFORE running terraform apply for any new instance."
