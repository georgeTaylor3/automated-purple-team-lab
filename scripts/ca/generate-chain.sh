#!/usr/bin/env bash
# generate-chain.sh
#
# Generates a full root -> intermediate -> leaf PQC (ML-DSA-65)
# certificate chain, using a pinned Alpine container for a
# reproducible, current OpenSSL build (Alpine 3.24 ships 3.5.8,
#
# Every generated key/cert gets a matching entry appended to
# crypto-inventory.jsonl -- a declarative record of what algorithm
# is used for what purpose, on what host.
# Intent is for all nodes/applications to add the algorithms its using to this 
# list for a project-level crypto inventory.
#
# This is a proof-of-concept / local-testing script. It generates
# a fresh root and intermediate every run, matching the eventual
# weekly-rebuild design, but does not yet integrate with Secret
# Manager or a real signing-request flow between hosts -- that's
# the next step once this pattern is proven.

set -euo pipefail

LEAF_CN="${1:?Usage: generate-chain.sh <leaf-common-name> <purpose> [output-dir]}"
PURPOSE="${2:?Usage: generate-chain.sh <leaf-common-name> <purpose> [output-dir]}"
OUT_DIR="${3:-./ca-output}"
ALPINE_IMAGE="alpine:3.24"
ALGO="mldsa65"
ALGO_LABEL="ML-DSA-65"
INVENTORY_FILE="$OUT_DIR/crypto-inventory.jsonl"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

run_openssl() {
  docker run --rm -v "$(pwd)":/work -w /work "$ALPINE_IMAGE" sh -c "
    apk add --no-cache openssl >/dev/null &&
    $1
  "
}

log_inventory() {
  local hostname="$1"
  local component="$2"
  local purpose="$3"
  local key_type="$4"
  local issued_by="$5"
  local cert_file="$6"

  local not_before not_after
  not_before=$(run_openssl "openssl x509 -in $cert_file -noout -startdate" | cut -d= -f2)
  not_after=$(run_openssl "openssl x509 -in $cert_file -noout -enddate" | cut -d= -f2)

  local not_before_iso not_after_iso generated_at_iso
  not_before_iso=$(date -u -d "$not_before" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$not_before")
  not_after_iso=$(date -u -d "$not_after" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$not_after")
  generated_at_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  python3 -c "
import json
entry = {
    'hostname': '$hostname',
    'component': '$component',
    'purpose': '$purpose',
    'algorithm': '$ALGO_LABEL',
    'algorithm_standard': 'NIST FIPS 204',
    'key_type': '$key_type',
    'post_quantum': True,
    'fips_140_3_validated_module': False,
    'issued_by': '$issued_by',
    'not_before': '$not_before_iso',
    'not_after': '$not_after_iso',
    'generated_at': '$generated_at_iso',
    'generation_method': 'openssl req -newkey $ALGO (alpine:3.24, openssl 3.5.8)'
}
print(json.dumps(entry))
" >> "$(basename "$INVENTORY_FILE")"
}

echo "Generating root CA..."
run_openssl "openssl req -x509 -newkey $ALGO -keyout root-ca.key -out root-ca.crt -days 3650 -nodes -subj '/CN=purple-lab-root-ca'"
log_inventory "control-node" "root CA" "signs the intermediate CA -- root of trust for the whole lab" "signature (CA)" "self-signed" "root-ca.crt"

echo "Generating intermediate CA..."
run_openssl "openssl req -newkey $ALGO -keyout intermediate-ca.key -out intermediate-ca.csr -nodes -subj '/CN=purple-lab-intermediate-ca'"
run_openssl "openssl x509 -req -in intermediate-ca.csr -CA root-ca.crt -CAkey root-ca.key -CAcreateserial -out intermediate-ca.crt -days 1825 -extfile <(printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign')"
log_inventory "control-node" "intermediate CA" "signs leaf certificates for all lab services" "signature (CA)" "purple-lab-root-ca" "intermediate-ca.crt"

echo "Generating leaf certificate for $LEAF_CN..."
run_openssl "openssl req -newkey $ALGO -keyout leaf.key -out leaf.csr -nodes -subj '/CN=$LEAF_CN'"
run_openssl "openssl x509 -req -in leaf.csr -CA intermediate-ca.crt -CAkey intermediate-ca.key -CAcreateserial -out leaf.crt -days 90"
log_inventory "$LEAF_CN" "leaf certificate" "$PURPOSE" "signature (end-entity)" "purple-lab-intermediate-ca" "leaf.crt"

cat leaf.crt intermediate-ca.crt > fullchain.crt

echo "Verifying chain..."
run_openssl "openssl verify -CAfile root-ca.crt -untrusted intermediate-ca.crt leaf.crt"

echo ""
echo "Done. Chain written to $OUT_DIR/, inventory entries appended to $INVENTORY_FILE"
