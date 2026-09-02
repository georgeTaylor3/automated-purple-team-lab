# NIST 800-53 Rev 5 Control Mapping

## Scope and honesty about what this is

NIST SP 800-53 Rev 5 contains 20 control families and well over 1,100
individual controls (base controls plus enhancements). This document does
not claim to map all of them -- that would be dishonest for a document
meant to function as an audit artifact.

Instead, this maps the control **families** most relevant to what this
project has actually built, citing specific **base controls** (not
enhancements) with reasonable confidence, and states plainly where a
control is fully addressed, partially addressed, or not yet addressed at
all. Anyone using this for real compliance work should verify each cited
control against the actual NIST SP 800-53 Rev 5 text
(https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) rather than trust
this summary alone.

**Structure note:** this is organized by control family so that a SOC 2
Trust Service Criteria mapping can be added later as a parallel column per
control family, without restructuring this document. SOC 2's Security,
Availability, and Confidentiality criteria map reasonably well onto
800-53's AC, AU, CM, CP, IA, and SC families; that mapping is not done
here yet.

**Last reviewed:** 2026-08-29 (initial draft, not yet independently
verified against NIST source text)

## Access Control (AC)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| AC-2 (Account Management) | Accounts created, scoped, reviewed, disabled when no longer needed | Addressed | Every service account named, scoped, and justified in `10-rbac-matrix.md`; discovered dynamically by `audit-rbac.sh` so nothing goes unreviewed |
| AC-3 (Access Enforcement) | System enforces approved authorizations | Addressed | Firewall rules matched to service account identity, not IP range (`05-firewall-trust-model.md`); IAM roles scoped per identity |
| AC-6 (Least Privilege) | Users/processes granted only the access they need | Addressed | Every custom role built permission-by-permission as gaps were discovered, not granted broadly upfront -- documented in `02-identity-and-access.md` and `07-troubleshooting-log.md` |
| AC-17 (Remote Access) | Remote access sessions authorized and monitored | Addressed | All admin access via IAP tunnel, no public SSH/RDP; firewall-scoped per identity |

## Audit and Accountability (AU)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| AU-2 (Event Logging) | Organization determines which events to log | Partially addressed | Firewall rule logging enabled (metadata excluded to reduce volume, per `05-firewall-trust-model.md`); no centralized security event logging yet -- Elastic Agent/Fleet exists but isn't yet ingesting from real target workloads |
| AU-6 (Audit Record Review) | Logs are reviewed for indications of inappropriate activity | Partially addressed | `rbac-diff.sh` provides automated review of IAM state specifically; no equivalent yet for general system/security logs |
| AU-9 (Protection of Audit Information) | Audit records protected from unauthorized access/modification | Addressed, for the RBAC baseline specifically | Signed baseline (`rbac-baseline.json.sig`) via `ssh-keygen -Y sign` -- tampering is detectable, not just theoretically preventable |
| AU-10 (Non-repudiation) | Actions can be traced to the individual who took them | Addressed, for RBAC and git history | Signed commits (SSH-based, YubiKey-backed) and signed RBAC baselines both provide this; not yet extended to runtime application actions |

## Configuration Management (CM)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| CM-2 (Baseline Configuration) | A known, approved baseline configuration is maintained | Addressed | Golden images (Packer) for every workload; Terraform state as the infrastructure baseline |
| CM-3 (Configuration Change Control) | Changes are proposed, reviewed, and approved before implementation | Partially addressed | Git + `terraform plan` review before every `apply` (practiced consistently throughout this project's history); no formal multi-party approval step, since this is currently a single-operator project |
| CM-6 (Configuration Settings) | Security configuration settings are established and enforced | Addressed | Documented, version-controlled Terraform/Packer/Compose configuration for every workload |
| CM-8 (System Component Inventory) | An inventory of system components is maintained | Addressed | `audit-rbac.sh` provides a live, dynamically-discovered inventory of every service account, secret, and custom role; golden images provide inventory of workload types |

## Identification and Authentication (IA)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| IA-2 (Identification and Authentication, Organizational Users) | Users uniquely identified and authenticated | Addressed | Human admin account uses YubiKey MFA; no shared credentials |
| IA-2(1)/(2) (MFA) | Multi-factor authentication for privileged/non-privileged accounts | Addressed | YubiKey 5 NFC for Google/GitHub; SSH commit signing also hardware-key-backed |
| IA-5 (Authenticator Management) | Credentials are protected, rotated, not hardcoded | Addressed | No service account keys anywhere in the project; all secrets in Secret Manager, rotated at least once already (Elastic/Kibana passwords) |
| IA-9 (Service Identification and Authentication) | Services/devices are uniquely identified | Addressed | Every workload has a distinct, named service account -- no shared or generic identities |

## Contingency Planning (CP)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| CP-9 (System Backup) | Backups of system data are conducted | Not addressed | No backup strategy yet for Elasticsearch data, CALDERA operations history, or Terraform state beyond what git/GCS naturally provides |
| CP-10 (System Recovery and Reconstitution) | System can be restored after a disruption | Partially addressed | Golden images + Terraform mean infrastructure itself is fully reproducible from code; data (Elasticsearch indices, CALDERA history) is not currently backed up separately |

## Risk Assessment (RA)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| RA-5 (Vulnerability Monitoring and Scanning) | Systems are scanned for vulnerabilities | Not addressed | No vulnerability scanning tooling integrated yet. This is also a planned project feature in its own right (STIG compliance posture vs. attack success) -- see `01-architecture.md` |

## System and Services Acquisition (SA)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| SA-4 (Acquisition Process) | Security requirements included in acquisition/build processes | Addressed | Every image build (`08-packer-image-pipeline.md`) pins specific software versions deliberately rather than trusting "latest"; documented reasoning for each pin |
| SA-11 (Developer Testing and Evaluation) | Security testing performed during development | Partially addressed | `scripts/security-scan` catches secrets before commit; no broader SAST/dependency scanning yet |

## System and Communications Protection (SC)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| SC-7 (Boundary Protection) | Network boundaries are monitored and controlled | Addressed | Explicit default-deny egress per identity, documented per-rule justification -- `05-firewall-trust-model.md`, `06-egress-and-nat.md` |
| SC-8 (Transmission Confidentiality and Integrity) | Data in transit is protected | Partially addressed | Internal service-to-service traffic deliberately plain-HTTP/self-signed (justified, documented, scoped to a network no external party can reach -- `09-public-tls-and-domain.md`); the one public-facing surface planned for real TLS is not yet built |
| SC-12 (Cryptographic Key Establishment and Management) | Keys are managed securely | Addressed | Secret Manager for application secrets; hardware-backed (YubiKey) keys for human identity and code/artifact signing |
| SC-28 (Protection of Information at Rest) | Data at rest is protected | Partially addressed | Secrets encrypted via Secret Manager; Elasticsearch data at rest not separately encrypted beyond GCP's default disk encryption |

## System and Information Integrity (SI)

| Control | Description (summary) | Status | Evidence |
|---|---|---|---|
| SI-2 (Flaw Remediation) | Flaws are identified and corrected | Addressed as a practice | `07-troubleshooting-log.md` documents real flaws found and fixed throughout the project's history, not hidden |
| SI-4 (System Monitoring) | Systems are monitored to detect attacks and indicators of compromise | Not addressed yet | This is the project's actual end-goal (CALDERA + Elastic detection loop), not yet operational against a real target workload |

## Families not yet addressed at all

The following families have no meaningful coverage yet and are not
claimed above: **AT** (Awareness and Training -- not applicable to a
single-operator project, but would be required for a real client), **CA**
(Assessment, Authorization, and Monitoring), **MA** (Maintenance), **MP**
(Media Protection), **PE** (Physical and Environmental Protection -- not
directly applicable, since this runs on GCP, but the shared-responsibility
boundary with GCP's own PE controls is not documented here), **PL**
(Planning), **PM** (Program Management), **PS** (Personnel Security), **PT**
(PII Processing and Transparency -- not applicable, no PII processed),
**SR** (Supply Chain Risk Management -- partially relevant given pinned
software versions, but not formally addressed as a supply-chain control).

## Next steps

- Verify every cited control above against the actual NIST SP 800-53
  Rev 5 text before using this for real compliance work.
- Decide whether "Not addressed" items are genuinely out of scope for
  this project's purpose, or worth building toward.
- When ready, add a SOC 2 Trust Service Criteria column per family,
  reusing this same structure.
