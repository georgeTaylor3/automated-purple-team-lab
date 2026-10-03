#!/usr/bin/env bash
# purple-lab-deploy.sh
#
# Baked into the control-node image (via Packer's file provisioner,
# installed to /usr/local/bin/) -- this is an exception
# to "everything runs from the freshly-pulled repo." It has to be,
# since its own first job is fetching that fresh repo in the first
# place; nothing can pull itself (probably). Everything AFTER that point calls
# scripts by their path inside the freshly-pulled $REPO_DIR, not
# separately-baked copies -- a bug fix to any of those just needs a
# normal git push and the next boot/timer cycle, no Packer rebuild.

set -euo pipefail
REPO_DIR=/opt/purple-lab
REPO_URL="__REPO_URL__"
MARKER_FILE="$REPO_DIR/.last-built-commit"

if [ -d "$REPO_DIR/.git" ]; then
  echo "Repo exists, pulling latest..."
  cd "$REPO_DIR"
  git pull
else
  echo "Cloning $REPO_URL..."
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
fi

echo "Applying host-based firewall..."
"$REPO_DIR/scripts/security/verify-nftables.sh" "$REPO_DIR/scripts/security/control-node-nftables.conf" || echo "Firewall verification script itself failed to run -- non-fatal, continuing."

echo "Fetching secrets from Secret Manager..."
ELASTIC_PASSWORD=$(gcloud secrets versions access latest --secret=elastic-password)
KIBANA_SYSTEM_PASSWORD=$(gcloud secrets versions access latest --secret=kibana-system-password)
KIBANA_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret=kibana-encryption-key)
FLEET_SERVER_SERVICE_TOKEN=$(gcloud secrets versions access latest --secret=fleet-server-service-token)
cat > "$REPO_DIR/.env" <<ENVFILE
ELASTIC_PASSWORD=$ELASTIC_PASSWORD
KIBANA_SYSTEM_PASSWORD=$KIBANA_SYSTEM_PASSWORD
KIBANA_ENCRYPTION_KEY=$KIBANA_ENCRYPTION_KEY
FLEET_SERVER_SERVICE_TOKEN=$FLEET_SERVER_SERVICE_TOKEN
ENVFILE
chmod 600 "$REPO_DIR/.env"

docker compose up -d elasticsearch

echo "Waiting for Elasticsearch to accept requests..."
curl -s -o /dev/null --retry 30 --retry-delay 5 --retry-connrefused \
  -u "elastic:$ELASTIC_PASSWORD" http://localhost:9200 || true

echo "Syncing kibana_system password (needed every time Elasticsearch's data volume starts fresh -- setting ELASTICSEARCH_PASSWORD in Kibana's environment does not itself change the password Elasticsearch expects)..."
curl -s -u "elastic:$ELASTIC_PASSWORD" -X POST "http://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}"
echo

CURRENT_COMMIT=$(git rev-parse HEAD)
LAST_BUILT_COMMIT=""
if [ -f "$MARKER_FILE" ]; then
  LAST_BUILT_COMMIT=$(cat "$MARKER_FILE")
fi

if [ "$CURRENT_COMMIT" != "$LAST_BUILT_COMMIT" ]; then
  echo "New commit detected ($CURRENT_COMMIT), rebuilding..."
  docker compose build
  echo "$CURRENT_COMMIT" > "$MARKER_FILE"
else
  echo "No changes since last build ($CURRENT_COMMIT), skipping rebuild."
fi

docker compose up -d elasticsearch kibana caldera fleet-server

echo "Waiting for CALDERA to accept requests..."
curl -s -o /dev/null --retry 30 --retry-delay 5 --retry-connrefused \
  http://localhost:8888 || true

# Fleet-specific readiness, not just "is Kibana's base HTTP server
# listening" -- confirmed the hard way: Kibana's own HTTP port can
# accept connections well before its Fleet plugin has finished its
# own, separate initialization. A generic port check was satisfied
# while Fleet's real API still returned nothing, causing Fleet
# policy provisioning below to fail with empty, non-JSON responses
# even though CALDERA/Elasticsearch were genuinely fine. This probes
# the actual endpoint ensure-fleet-policies.py depends on, not a
# proxy for it.
echo "Waiting for Kibana's Fleet API to accept requests..."
curl -s -o /dev/null --retry 30 --retry-delay 5 --retry-connrefused \
  -u "elastic:$ELASTIC_PASSWORD" -H "kbn-xsrf: true" -H "elastic-api-version: 2023-10-31" \
  http://localhost:5601/api/fleet/agent_policies || true

# Retried, not a single attempt -- confirmed the hard way: the CALDERA
# readiness check above only confirms the HTTP port is listening, not
# that the startup banner (containing this password) has actually
# finished printing to the container's own log yet. A single
# extraction attempt immediately after the port check can genuinely
# run before the password line exists.
echo "Extracting fresh CALDERA red password from boot log..."
CALDERA_FRESH_PASSWORD=""
for _ in $(seq 1 12); do
  CALDERA_FRESH_PASSWORD=$(docker compose logs caldera 2>&1 | sed -E 's/^caldera +\| ?//' | awk '
    /USERNAME: red/ { in_red=1 }
    in_red && /PASSWORD:/ { in_pw=1; next }
    in_red && in_pw && /API_TOKEN:/ { in_pw=0; in_red=0 }
    in_pw { gsub(/[[:space:]]/, ""); printf "%s", $0 }
  ')
  if [ -n "$CALDERA_FRESH_PASSWORD" ]; then
    break
  fi
  sleep 5
done

if [ -z "$CALDERA_FRESH_PASSWORD" ]; then
  echo "WARNING: could not extract fresh CALDERA password from log -- Secret Manager not updated."
else
  echo -n "$CALDERA_FRESH_PASSWORD" | gcloud secrets versions add caldera-red-password --data-file=-
  echo "Fresh CALDERA red password published to Secret Manager."
fi

echo "Running CALDERA agent cleanup..."
# Invoked via bash explicitly, not executed directly -- confirmed the
# hard way: calling these scripts from the freshly-pulled repo
# (rather than a Packer-installed /usr/local/bin/ copy, which used to
# get an explicit chmod +x at build time) means nothing ever marks
# them executable after a fresh git clone. Running them through bash
# works regardless of the file's own executable bit.
bash "$REPO_DIR/scripts/caldera-agent-cleanup.sh" || echo "Cleanup failed or found nothing to clean -- non-fatal."

echo "Ensuring CALDERA abilities/adversaries are present..."
bash "$REPO_DIR/scripts/ensure-caldera-abilities.sh" || echo "Ability provisioning failed -- non-fatal."

echo "Ensuring Fleet agent policies are present..."
export ELASTIC_PASSWORD
python3 "$REPO_DIR/ca/ensure-fleet-policies.py" || echo "Fleet policy provisioning failed -- non-fatal."

echo "purple-lab-deploy.sh complete."
