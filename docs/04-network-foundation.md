# Network Foundation

The project uses a custom Google Cloud VPC named `purple-team-vpc`.

The initial network has separate subnets for control systems and target
systems. Keeping the two roles separate yields clear boundary where
firewall policy can be added as the environment develops.

## Current layout

The control subnet is:

- Name: `control-subnet`
- CIDR: `10.60.10.0/24`
- Region: `us-central1`
- Private Google Access: enabled

This subnet is for CALDERA and other control-side systems.

The target subnet is:

- Name: `target-subnet`
- CIDR: `10.60.20.0/24`
- Region: `us-central1`
- Private Google Access: enabled

This subnet is for systems used as targets.

The larger `10.60.0.0/16` range is only an address-planning convention for
this project. It is not assigned to the VPC itself. Additional subnets can be
added from this range later without changing the current subnet addresses.

## Current security posture

The network foundation does not (at the moment) create virtual machines, public VM
IP addresses, Cloud NAT, public SSH access, public CALDERA access, or custom
firewall allow rules.

Network access will be added deliberately as the systems that require it are
introduced.

The target network is separate from the control network so future firewall
policy can limit which systems and protocols are allowed across that boundary.

## Terraform access

Terraform manages the VPC and subnets by impersonating the dedicated
`terraform-deployer` service account.

The service account has Compute Network Admin permissions for this phase.

Firewall permissions are intentionally handled separately and will be added
only when firewall resources are introduced.

## Terraform state

Terraform state is stored in a private Google Cloud Storage bucket.

The state bucket uses uniform bucket-level access, public access prevention,
object versioning, and soft-delete protection.

The real bucket name and backend service-account configuration are stored in
the local ignored `backend.hcl` file.

`backend.hcl.example` documents the expected configuration without publishing
environment-specific values.

Terraform state files and saved execution plans are excluded from Git.
