#!/usr/bin/env bash
# web-target-setup.sh
#
# Runs once at instance boot on web-target. nginx and the Juice Shop
# Docker image are already baked into the golden image
# (packer/web-target) -- this generates a fresh, instance-specific
# self-signed cert, configures and starts nginx as a reverse proxy,
# starts the Juice Shop container, then enrolls Elastic Agent (also
# already baked in).
#
# Required instance metadata keys (set via Terraform):
#   fleet-url
#   fleet-enrollment-token

set -euo pipefail

LOG_FILE="/var/log/web-target-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- web-target-setup starting: $(date -u +%FT%TZ) ---"

# -----------------------------------------------------------------------
# nginx: cert generation and config, deferred from image-build time.
# Reverse-proxies to Juice Shop, listening only on 127.0.0.1:3000 --
# the vulnerable app itself is never directly reachable on the network,
# only through nginx's TLS-terminated 443.
# -----------------------------------------------------------------------

if [ ! -f /etc/nginx/ssl/web-target.crt ]; then
  echo "Generating self-signed cert..."
  sudo mkdir -p /etc/nginx/ssl
  sudo openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/web-target.key \
    -out /etc/nginx/ssl/web-target.crt \
    -subj "/CN=web-target.internal"

  sudo tee /etc/nginx/sites-available/web-target > /dev/null <<'NGINXCONF'
server {
    listen 443 ssl default_server;
    ssl_certificate     /etc/nginx/ssl/web-target.crt;
    ssl_certificate_key /etc/nginx/ssl/web-target.key;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXCONF

  sudo ln -sf /etc/nginx/sites-available/web-target /etc/nginx/sites-enabled/web-target
  sudo rm -f /etc/nginx/sites-enabled/default
  echo "nginx configured."
else
  echo "nginx cert/config already present. Skipping generation."
fi

sudo systemctl enable nginx
sudo systemctl restart nginx
echo "nginx running on 443."

# -----------------------------------------------------------------------
# Juice Shop: image already baked in at build time (packer/web-target).
# Bound to 127.0.0.1 only -- nginx is the only path to it.
# -----------------------------------------------------------------------

if ! sudo docker ps --format '{{.Names}}' | grep -q '^juice-shop$'; then
  echo "Starting Juice Shop..."
  sudo docker run -d --restart unless-stopped \
    -p 127.0.0.1:3000:3000 \
    --name juice-shop \
    bkimminich/juice-shop:v20.1.1
  echo "Juice Shop started."
else
  echo "Juice Shop container already running. Skipping."
fi

# -----------------------------------------------------------------------
# Elastic Agent enrollment -- same logic as boot-agent-enrollment.sh.
# -----------------------------------------------------------------------

get_metadata() {
  local key="$1"
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}" \
    || echo ""
}

FLEET_URL=$(get_metadata "fleet-url")
FLEET_ENROLLMENT_TOKEN=$(get_metadata "fleet-enrollment-token")

AGENT_BIN="/opt/elastic/elastic-agent/elastic-agent"

if [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
  echo "Skipping Elastic Agent enrollment: fleet-url or fleet-enrollment-token metadata not set."
  exit 0
fi

if [ ! -x "$AGENT_BIN" ]; then
  echo "ERROR: Elastic Agent binary not found at $AGENT_BIN. Was it baked into this image?"
  exit 1
fi

if "$AGENT_BIN" status >/dev/null 2>&1; then
  echo "Elastic Agent already installed and running. Skipping enrollment."
  exit 0
fi

echo "Enrolling Elastic Agent with Fleet at $FLEET_URL ..."

FLEET_HOST=$(echo "$FLEET_URL" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')
FLEET_PORT=$(echo "$FLEET_URL" | sed -E 's#^.*:([0-9]+).*$#\1#')

echo "Waiting for Fleet Server at ${FLEET_HOST}:${FLEET_PORT} to become reachable..."
FLEET_REACHABLE=0
for i in $(seq 1 20); do
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${FLEET_HOST}/${FLEET_PORT}" 2>/dev/null; then
    FLEET_REACHABLE=1
    echo "Fleet Server reachable after $((i - 1)) retries."
    break
  fi
  echo "  Fleet Server not reachable yet (attempt $i/20), waiting 15s..."
  sleep 15
done

if [ "$FLEET_REACHABLE" -ne 1 ]; then
  echo "ERROR: Fleet Server at ${FLEET_HOST}:${FLEET_PORT} was not reachable after 20 attempts (~5 minutes)."
  echo "control-node may not be running. Enrollment not attempted -- rerun this script manually once control-node is confirmed up:"
  echo "  sudo google_metadata_script_runner startup"
  exit 1
fi

"$AGENT_BIN" install \
  --url="$FLEET_URL" \
  --enrollment-token="$FLEET_ENROLLMENT_TOKEN" \
  --insecure \
  --non-interactive \
  --force

echo "--- web-target-setup finished: $(date -u +%FT%TZ) ---"
