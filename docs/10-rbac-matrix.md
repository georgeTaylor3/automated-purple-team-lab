# Role-Based Access Control (RBAC) Matrix

## Purpose

This document is an auditable inventory of every identity in this project,
what it can do, and why. It exists to answer three questions for a reviewer:

1. Who or what can act in this environment?
2. What is each identity actually permitted to do?
3. Is each permission scoped to what that identity genuinely needs?

This is a point-in-time snapshot, not a live source of truth. Verify against
the actual project before relying on it -- see "Verification commands"
at the end.

**Last compiled:** 2026-08-29
**Project:** `purple-lab-48271` (Automated Purple Team Lab)

## Principle

Every identity in this project is scoped to the narrowest set of
permissions it needs to do its one job. No identity holds a broad
predefined role (e.g. `Editor`, `Owner`) except the single human admin
account. Where a predefined Google role was used, it's noted as broader
than ideal and flagged for future tightening.

## Human identities

| Identity | Type | Authentication | Role(s) | Scope | Justification |
|---|---|---|---|---|---|
| Admin (project owner) | Human | Google Account, YubiKey 5 NFC (2SV) | `roles/owner` | Project-wide | Sole admin identity. All automation impersonates a scoped service account rather than acting as this identity directly. |

## Service accounts

| Identity | Purpose | IAM Role(s) | Scope | Justification |
|---|---|---|---|---|
| `terraform-deployer` | Runs all Terraform apply/plan operations, impersonated via ADC from the admin account -- never runs as the admin identity directly | `terraformFirewallManager` (custom) | Project | Firewall rule CRUD only -- create/read/list/update/delete on `google_compute_firewall` resources |
| | | `terraformComputeInstanceManager` (custom) | Project | Compute instance/disk lifecycle (create/delete/get/list/setLabels/setMetadata/setServiceAccount) -- needed once Terraform began managing `control-node` |
| | | `roles/iam.roleAdmin` | Project | Create/manage custom IAM role definitions (predefined role -- broader than ideal, no narrower equivalent exists for this capability) |
| | | `roles/resourcemanager.projectIamAdmin` | Project | Bind IAM roles to members -- distinct from role *creation* above; discovered as a gap when Terraform first tried to grant Secret Manager access (predefined role -- broader than ideal) |
| | | `roles/secretmanager.admin` | Project | Manage Secret Manager resources and their IAM policies (predefined role -- broader than ideal; no secrets existed before this was needed) |
| | | `roles/iam.serviceAccountUser` | Scoped to `control-node-sa` only (not project-wide) | Attach `control-node-sa` to the `control-node` instance at creation time |
| `packer-deployer` | Runs all Packer builds, impersonated via ADC -- never runs as the admin identity directly | `packerImageBuilder` (custom) | Project | Temporary builder VM/disk lifecycle, serial port read, metadata/label/service-account assignment |
| | | `packerImageManager` (custom) | Project | Custom image lifecycle: create/get/list/delete/deprecate/useReadOnly |
| | | `roles/iap.tunnelResourceAccessor` | Conditional: `destination.port == 5986` (WinRM) | IAP tunnel to temporary Windows builders only |
| | | `roles/iap.tunnelResourceAccessor` | Conditional: `destination.port == 22` (SSH) | IAP tunnel to temporary Linux (Ubuntu/CALDERA-VM/control-node) builders only |
| `packer-builder-sa` | Runtime identity attached to temporary Packer builder VMs -- not a permanent workload | `roles/logging.logWriter` | Project | Allow the build-time guest agent to write logs |
| | | *(no other IAM roles)* | | Network access is entirely firewall-based, not IAM-based -- see Network-level access below |
| `control-node-sa` | Runtime identity for the persistent `control-node` instance (CALDERA + Elasticsearch + Kibana, Fleet Server pending) | `roles/secretmanager.secretAccessor` | Scoped to secret `elastic-password` only | Read the Elasticsearch superuser password at boot |
| | | `roles/secretmanager.secretAccessor` | Scoped to secret `kibana-system-password` only | Read Kibana's service-account password at boot |
| | | `roles/secretmanager.secretAccessor` | Scoped to secret `kibana-encryption-key` only | Read Kibana's saved-objects encryption key at boot |
| | | *(no project-level IAM roles)* | | Network access is entirely firewall-based, not IAM-based |
| `web-target-sa` | Runtime identity for the future web-server target workload | *(no IAM roles)* | | Not yet deployed as a live Compute Engine instance. Exists today only as a firewall selector. |
| `workstation-target-sa` | Runtime identity for the future workstation target workload | *(no IAM roles)* | | Not yet deployed as a live Compute Engine instance. Exists today only as a firewall selector. |

## Network-level access (the other half of least privilege)

Several identities above have no IAM roles at all -- `packer-builder-sa`,
`control-node-sa`, `web-target-sa`, `workstation-target-sa`. Their actual
capability boundary is enforced entirely by VPC firewall rules matched to
their service account identity, not by IAM. This is deliberate: these are
workload identities, not control-plane identities, so their trust boundary
is "what can this thing talk to on the network," not "what Google Cloud
APIs can this thing call." See `05-firewall-trust-model.md` for the full
rule set.

## Secrets inventory

| Secret | Who can read it | Purpose |
|---|---|---|
| `elastic-password` | `control-node-sa` | Elasticsearch `elastic` superuser password |
| `kibana-system-password` | `control-node-sa` | Kibana's `kibana_system` service account password |
| `kibana-encryption-key` | `control-node-sa` | Kibana saved-objects encryption key (required for Fleet) |
| `fleet-server-service-token` | *(not yet created)* | Planned: Fleet Server's own Elasticsearch service token |

No secret is readable by more than one identity. No secret is readable by
any human account directly through this project's IAM (the admin account's
`roles/owner` grants implicit access as project owner, which is a known,
accepted exception rather than a per-secret grant).

## Custom roles, full permission lists

### terraformFirewallManager
Firewall rule CRUD (see `05-firewall-trust-model.md` for the exact
permission list).

### terraformComputeInstanceManager
```
compute.instances.create
compute.instances.delete
compute.instances.get
compute.instances.list
compute.instances.setLabels
compute.instances.setMetadata
compute.instances.setServiceAccount
compute.disks.create
compute.disks.delete
compute.disks.get
compute.disks.use
compute.images.useReadOnly
compute.subnetworks.use
compute.subnetworks.get
compute.networks.get
compute.zones.get
compute.machineTypes.get
compute.globalOperations.get
compute.zoneOperations.get
```

### packerImageBuilder
```
compute.disks.create
compute.disks.delete
compute.disks.get
compute.disks.use
compute.disks.useReadOnly
compute.globalOperations.get
compute.images.create
compute.images.get
compute.images.list
compute.instances.create
compute.instances.delete
compute.instances.get
compute.instances.getSerialPortOutput
compute.instances.setLabels
compute.instances.setMetadata
compute.instances.setServiceAccount
compute.instances.stop
compute.machineTypes.get
compute.networks.get
compute.projects.get
compute.regions.get
compute.subnetworks.get
compute.zoneOperations.get
compute.zones.get
```

### packerImageManager
```
compute.images.create
compute.images.get
compute.images.list
compute.images.delete
compute.images.deprecate
compute.images.useReadOnly
```

## Known gaps / not yet reviewed

- `roles/iam.roleAdmin`, `roles/resourcemanager.projectIamAdmin`, and
  `roles/secretmanager.admin` on `terraform-deployer` are predefined
  Google roles broader than a perfectly scoped custom role would be. No
  narrower predefined or practical custom equivalent was found for any of
  the three. Worth revisiting if this project's IAM surface grows further.
- `web-target-sa` and `workstation-target-sa` have no IAM roles because
  they have no live workload yet -- this table will need a real entry
  once those targets are deployed.
- Fleet Server's service token doesn't exist yet -- `fleet-server-service-token`
  is listed as planned, not live.
- This document was compiled by hand from project history, not generated
  from a live policy export. Treat it as a draft pending verification
  (see below).

## Verification commands

Run these against the live project and diff the output against this
document before treating it as authoritative:

```bash
# All IAM bindings for a given service account
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:SERVICE_ACCOUNT_EMAIL" \
  --format="table(bindings.role,bindings.condition.title,bindings.condition.expression)"

# Full custom role permission list
gcloud iam roles describe ROLE_ID --project="$PROJECT_ID"

# Secret Manager access for a specific secret
gcloud secrets get-iam-policy SECRET_NAME --project="$PROJECT_ID"

# Every secret in the project
gcloud secrets list --project="$PROJECT_ID"

# Every service account in the project
gcloud iam service-accounts list --project="$PROJECT_ID"
```
