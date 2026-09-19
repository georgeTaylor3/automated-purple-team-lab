#!/usr/bin/env bash
# caldera-agent-cleanup.sh
#
# Purges duplicate CALDERA agent records, keeping only the
# most-recently-seen agent per hostname. Fresh identities (no -paw)
# since a prior session's trust-timer fix mean every deliberate
# instance stop/start creates a new agent record -- this removes the
# leftover older ones for the same host, regardless of how much time
# has passed. Grouped by hostname rather than a fixed age threshold,
# so the current agent for any host is never accidentally deleted
# just because the lab sat unused for a while.
#
# Password fetched from Secret Manager, never hardcoded -- requires
# control-node-sa to hold secretAccessor on caldera-red-password.

set -euo pipefail

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/project/project-id")

CALDERA_RED_PASSWORD=$(gcloud secrets versions access latest \
  --secret=caldera-red-password --project="$PROJECT_ID")

COOKIE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_FILE"' EXIT

curl -s -c "$COOKIE_FILE" -X POST http://localhost:8888/enter \
  -d "username=red&password=$CALDERA_RED_PASSWORD" > /dev/null

echo "Checking for duplicate agents per hostname..."

DUPLICATE_PAWS=$(curl -s -b "$COOKIE_FILE" http://localhost:8888/api/v2/agents | python3 -c "
import json, sys
from collections import defaultdict

agents = json.load(sys.stdin)
by_host = defaultdict(list)
for a in agents:
    by_host[a['host']].append(a)

for host, group in by_host.items():
    # Keep the one with the most recent last_seen; every other entry
    # for this same host is a stale leftover from an earlier boot.
    group.sort(key=lambda a: a['last_seen'], reverse=True)
    for a in group[1:]:
        print(a['paw'])
")

if [ -z "$DUPLICATE_PAWS" ]; then
  echo "No duplicate agents found. Every host has exactly one record."
  exit 0
fi

echo "$DUPLICATE_PAWS" | while read -r paw; do
  echo "Deleting stale duplicate: $paw"
  curl -s -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE -b "$COOKIE_FILE" \
    "http://localhost:8888/api/v2/agents/$paw"
done

echo "Cleanup complete."
