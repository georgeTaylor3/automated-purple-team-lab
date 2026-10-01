#!/usr/bin/env bash
# close-lab-tunnels.sh
#
# Kills IAP tunnels to control-node's CALDERA (8888) and Kibana
# (5601) ports, matched precisely by port number in the process's
# own command line -- never a broad "kill all ssh" pattern, so this
# can't accidentally take down an unrelated SSH session. Each port
# is handled independently, same as open-lab-tunnels.sh: a failure
# or absence on one never stops the attempt on the other.

set -uo pipefail

close_tunnel() {
  local port="$1"
  local label="$2"

  # Matches only a tunnel for THIS exact port -- e.g. "-L 8888:localhost:8888"
  # -- not any other ssh process that happens to be running.
  local pids
  pids=$(pgrep -f -- "-L ${port}:localhost:${port}" || true)

  if [ -z "$pids" ]; then
    echo "[$label] No tunnel found on port $port -- nothing to close."
    return 0
  fi

  echo "[$label] Found tunnel process(es) on port $port: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null

  sleep 1

  local still_running
  still_running=$(pgrep -f -- "-L ${port}:localhost:${port}" || true)
  if [ -z "$still_running" ]; then
    echo "[$label] Closed successfully."
  else
    echo "[$label] WARNING: process(es) $still_running did not exit after SIGTERM -- forcing."
    # shellcheck disable=SC2086
    kill -9 $still_running 2>/dev/null
    echo "[$label] Force-killed."
  fi
}

close_tunnel 8888 "CALDERA"
close_tunnel 5601 "Kibana"

echo ""
echo "Done. Remaining tunnel processes, if any:"
pgrep -af "compute ssh control-node" || echo "  (none found)"
