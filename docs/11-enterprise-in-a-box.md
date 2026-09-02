# Enterprise in a Box

## The thesis

A business needs IT infrastructure. They hire us. We get their
requirements, show up, and build their infrastructure from Layer 2 through
Layer 7 -- with documented architecture and the security artifacts a real
engagement requires, not just a working system.

This project is a working demonstration of that capability, built solo,
end to end, with every decision documented and every control provably
enforced rather than just claimed.

## What this project actually demonstrates

Mapped against what a real client engagement requires:

| Client requirement | What this project has |
|---|---|
| Network design (L2/L3) | VPC, subnetting, identity-based (not just IP-based) firewall segmentation -- `04-network-foundation.md`, `05-firewall-trust-model.md` |
| Infrastructure as code | Full Terraform + Packer pipeline, nothing hand-clicked in the console -- `03-terraform-bootstrap.md`, `08-packer-image-pipeline.md` |
| Identity and access management | Named, scoped service accounts for every automated process, least-privilege custom IAM roles, human MFA -- `02-identity-and-access.md` |
| Documented architecture | Diagrams and prose for network topology, IAM trust relationships, and the container architecture -- `docs/svg/` |
| Secrets management | Centralized secret storage (Secret Manager), scoped per-consumer access, nothing in source control -- referenced throughout |
| Auditable access control | A signed, diffable RBAC baseline -- not just a document claiming what access exists, but a script that proves it -- `10-rbac-matrix.md`, `rbac-baseline.sh`, `rbac-diff.sh` |
| Application layer (L7) | Self-hosted SIEM (Elasticsearch/Kibana), fleet management (Fleet Server), adversary emulation (CALDERA) -- `control-node-architecture.svg` |
| Incident/debugging history | An honest record of what broke and how it was fixed, not a sanitized success story -- `07-troubleshooting-log.md` |

## What a real engagement would still need, that this doesn't have yet

Naming these honestly matters more than pretending the list is shorter than
it is:

- **A documented change-management process**, not just the tooling. Git
  and Terraform are the *mechanism*; a real client wants to know *who
  approves what* and how rollback actually works in practice.
- **Incident response.** Nothing here yet answers "what happens when
  something breaks at 2am" as an actual runbook, only as a debugging log
  after the fact.
- **Client-side RBAC.** The RBAC matrix here covers *this project's own*
  infrastructure identities. A real engagement also needs role
  definitions for the client's own human staff -- who in their
  organization can touch what.
- **Compliance framework mapping.** See `12-nist-800-53-mapping.md` for
  the start of this -- most client engagements want controls mapped to a
  named framework (NIST 800-53, SOC 2, CIS) rather than described in the
  vendor's own words alone.
- **A repeatable client onboarding process.** This project has one
  environment, built for one purpose. A real "enterprise in a box"
  offering needs the same rigor applied repeatably across different
  clients with different requirements.

## Why this matters as a portfolio piece

Most personal infrastructure projects stop at "it works." The
differentiator here is "it works, and here is proof it works the way it's
supposed to" -- a signed RBAC baseline that can't be quietly hand-edited,
a documented network trust model instead of an implicit one, a
troubleshooting log that shows real debugging rather than a polished
after-the-fact narrative.

That gap -- between "I built a homelab" and "I can execute the technical
foundation a real client engagement is built on" -- is the actual claim
this project is making.
