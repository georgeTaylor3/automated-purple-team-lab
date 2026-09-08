# CALDERA and Elastic API Reference

Useful commands for checking status and driving both systems directly via
API, rather than the browser UI -- captured after a session where the
browser tunnel became unreliable but SSH stayed solid. Every command here
runs from an SSH session on `control-node` itself, so all traffic is
`localhost`, no tunnel round-trip needed.

```bash
gcloud compute ssh control-node --zone=us-central1-a --project="$PROJECT_ID" --tunnel-through-iap
```

## CALDERA

CALDERA's API keys are stored hashed (argon2), not recoverable in
plaintext from `conf/default.yml` even with container access. Instead of
the API key, authenticate via the same session-cookie login the web UI
itself uses:

### Log in and save a session cookie

```bash
curl -c /tmp/caldera_cookies.txt -X POST http://localhost:8888/enter \
  -d "username=red&password=admin"
```

A `302: Found` response means success. Every command below uses `-b
/tmp/caldera_cookies.txt` to reuse that session.

### List agents (confirm one is alive/trusted)

```bash
curl -s -b /tmp/caldera_cookies.txt http://localhost:8888/api/v2/agents \
  | python3 -m json.tool
```

Look for `"trusted": true` and a recent `"last_seen"` timestamp.

### List adversary profiles (find an ID to launch)

```bash
curl -s -b /tmp/caldera_cookies.txt http://localhost:8888/api/v2/adversaries \
  | python3 -m json.tool | grep -B3 '"name"'
```

### Launch an operation

```bash
curl -s -X POST -b /tmp/caldera_cookies.txt -H "Content-Type: application/json" \
  http://localhost:8888/api/v2/operations \
  -d '{"name":"OPERATION_NAME","adversary":{"adversary_id":"ADVERSARY_ID"},"group":"red","state":"running","autonomous":1}'
```

Save the `"id"` from the response -- every status check below needs it.

### Check operation progress

The operation's own executed steps live in the `chain` field, not
`host_group[].links` (that field shows an agent's general link history,
not this specific operation's progress -- easy to mix up).

```bash
curl -s -b /tmp/caldera_cookies.txt \
  http://localhost:8888/api/v2/operations/OPERATION_ID | python3 -c "
import json, sys
data = json.load(sys.stdin)
chain = data.get('chain', [])
print('State:', data.get('state'))
print('Total steps:', len(chain))
for l in chain:
    print(f\"  {l.get('finish')} — {l['ability']['technique_name']} (status={l['status']})\")
"
```

`status: 0` = success. A negative status is a non-success result (exact
meaning not fully confirmed -- worth checking CALDERA's own docs if it
matters for a specific investigation).

### See which techniques actually ran, deduplicated

```bash
curl -s -b /tmp/caldera_cookies.txt \
  http://localhost:8888/api/v2/operations/OPERATION_ID | python3 -c "
import json, sys
from collections import Counter
data = json.load(sys.stdin)
chain = data.get('chain', [])
names = Counter(l['ability']['technique_name'] for l in chain)
for name, count in names.items():
    print(f'  {name}: {count}')
"
```

### Close an operation manually

```bash
curl -s -X PUT -b /tmp/caldera_cookies.txt -H "Content-Type: application/json" \
  http://localhost:8888/api/v2/operations/OPERATION_ID \
  -d '{"state":"finished"}'
```

## Elasticsearch

Query directly, bypassing Kibana's UI entirely -- useful for confirming
correlation between a CALDERA step and real detection data without
needing the browser at all.

### Recent process events for a specific host

```bash
curl -s -u 'elastic:ELASTIC_PASSWORD' \
  "http://localhost:9200/logs-*/_search?q=host.name:HOSTNAME%20AND%20event.category:process&sort=@timestamp:desc&size=5" \
  | python3 -m json.tool
```

Remember to single-quote the `-u user:password` value if the password
contains `!` or other shell-special characters -- otherwise bash tries to
expand it as a history reference.

### Rotate the elastic superuser password (if ever locked out)

If the password itself is unknown/lost, Elasticsearch's own reset tool
works without any existing credentials, since it operates directly on the
node rather than through the REST API:

```bash
cd /opt/purple-lab
sudo docker exec -it elasticsearch \
  /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
```

Always follow with pushing the new value to Secret Manager
(`elastic-password` secret) and, separately, syncing `kibana_system`'s
password the normal way (see `07-troubleshooting-log.md`), then
`docker compose up -d --force-recreate kibana` to pick it up.
