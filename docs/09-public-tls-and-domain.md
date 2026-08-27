# Public TLS and Domain

This lab has exactly one piece that should ever be reachable from the public
internet: the demo controller (and, if exposed directly rather than through
it, Kibana's read-only view). Everything else -- CALDERA, Elastic,
control-node itself -- is deliberately private, reachable only via IAP.

## The distinction that matters

Internal service-to-service traffic (Elasticsearch <-> Kibana <-> CALDERA,
all inside Docker's network on control-node) never reaches an external
browser. A self-signed cert, or plain HTTP, there is fine -- nobody outside
the container network ever sees it, so there's no trust decision to make.

A public demo visitor's browser is different: it needs a real, publicly
trusted certificate, or the browser shows a scary warning and the visitor
has to click through a self-signed cert warning to proceed. That's the
"looks sloppy and is unsafe" problem, and it only applies to this one
public-facing surface.

## Domain

taylorhawley.net (already owned, used on a previous project) will be used
for the public-facing demo entry point once the demo controller exists.
Both a GCP-managed certificate and Let's Encrypt require a real domain to
issue against -- neither can issue a publicly trusted cert for a bare IP
address.

## Two implementation options, not yet decided

**GCP HTTPS Load Balancer with a Google-managed SSL certificate**
Google issues and auto-renews a real, publicly trusted cert for free,
sitting in front of whatever backend it's pointed at. No ACME client to
run or maintain. Has a real fixed hourly cost (roughly $18/month minimum)
even when idle, which is worth weighing against the project's low-cost
goal.

**A lightweight reverse proxy (Caddy is the simplest) on a VM with a real
public IP, using Let's Encrypt**
Genuinely free certs, but requires running and maintaining the proxy
yourself, and a public IP on whatever it's running on -- a departure from
the no-external-IP posture used everywhere else in this project so far.

## Status

Not yet decided which of the two to use. This is a "when the demo
controller exists" decision, not something blocking current Elastic/CALDERA
work -- the internal, self-signed/plain-HTTP setup used for
Elasticsearch/Kibana/CALDERA right now is correctly scoped to traffic that
never leaves the container network and doesn't need to change for this
reason.
