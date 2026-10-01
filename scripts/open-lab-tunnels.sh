#!/usr/bin/env bash
# open-lab-tunnels.sh
#
# Opens IAP tunnels to control-node's CALDERA (8888) and Kibana
# (5601) ports in the background. Each port is handled
# independently: already-open tunnels are skipped, and a failure on
# one port never prevents the other from being attempted -- this
# script deliberately does NOT use `set -e` for that reason.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZONE="us-central1-a"

if [ -z "${PROJECT_ID:-}" ]; then
  echo "PROJECT_ID not set -- sourcing scripts/set-lab-vars.sh first."
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/set-lab-vars.sh"
fi

is_port_open() {
  local port="$1"
  ss -tln 2>/dev/null | grep -q ":${port} "
}

open_tunnel() {
  local port="$1"
  local label="$2"

  if is_port_open "$port"; then
    echo "[$label] Tunnel already open on port $port -- skipping."
    return 0
  fi

  echo "[$label] No existing tunnel on port $port -- attempting to open one..."
  nohup gcloud compute ssh control-node --zone="$ZONE" --project="$PROJECT_ID" \
    --tunnel-through-iap -- -L "${port}:localhost:${port}" -N \
    > "/tmp/tunnel-${port}.log" 2>&1 &
  local pid=$!

  sleep 4

  if is_port_open "$port"; then
    echo "[$label] Tunnel established successfully (PID $pid, port $port)."
  else
    echo "[$label] WARNING: tunnel did not come up in time -- check /tmp/tunnel-${port}.log"
    echo "[$label] Continuing regardless -- this failure does not stop the script."
  fi
}

open_tunnel 8888 "CALDERA"
open_tunnel 5601 "Kibana"

echo ""
echo "Done. Active tunnel processes, if any:"
pgrep -af "compute ssh control-node" || echo "  (none found)"
