#!/usr/bin/env bash
# purple-lab-deploy.sh
#
# Baked into the control-node image (via Packer's file provisioner,
# installed to /usr/local/bin/) -- this is the one genuine exception
# to "everything runs from the freshly-pulled repo." It has to be,
# since its own first job is fetching that fresh repo in the first
# place; nothing can pull itself. Everything AFTER that point calls
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

echo "Waiting for Kibana to accept requests..."
curl -s -o /dev/null --retry 30 --retry-delay 5 --retry-connrefused \
  http://localhost:5601 || true

echo "Extracting fresh CALDERA red password from boot log..."
CALDERA_FRESH_PASSWORD=$(docker compose logs caldera 2>&1 | sed -E 's/^caldera +\| ?//' | awk '
  /USERNAME: red/ { in_red=1 }
  in_red && /PASSWORD:/ { in_pw=1; next }
  in_red && in_pw && /API_TOKEN:/ { in_pw=0; in_red=0 }
  in_pw { gsub(/[[:space:]]/, ""); printf "%s", $0 }
')

if [ -z "$CALDERA_FRESH_PASSWORD" ]; then
  echo "WARNING: could not extract fresh CALDERA password from log -- Secret Manager not updated."
else
  echo -n "$CALDERA_FRESH_PASSWORD" | gcloud secrets versions add caldera-red-password --data-file=-
  echo "Fresh CALDERA red password published to Secret Manager."
fi

echo "Running CALDERA agent cleanup..."
"$REPO_DIR/scripts/caldera-agent-cleanup.sh" || echo "Cleanup failed or found nothing to clean -- non-fatal."

echo "Ensuring CALDERA abilities/adversaries are present..."
"$REPO_DIR/scripts/ensure-caldera-abilities.sh" || echo "Ability provisioning failed -- non-fatal."

echo "Ensuring Fleet agent policies are present..."
export ELASTIC_PASSWORD
python3 "$REPO_DIR/ca/ensure-fleet-policies.py" || echo "Fleet policy provisioning failed -- non-fatal."

echo "purple-lab-deploy.sh complete."
