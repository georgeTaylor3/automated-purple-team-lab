# Identity and Access

## Goal

Different parts of the lab should use different accounts.

My admin account should not be used by the demo site or other automated
services.

The public demo account should have very limited access.

## My admin account

My admin accounts will use MFA.

When my YubiKey is available, I plan to use it where it is supported.

This may include:

- GitHub
- Google account
- Google Cloud
- Elastic Cloud
- SSH
- Git commit signing

I may also test YubiKey authentication for Linux admin access later.

## Service accounts

Automation should have its own account.

Examples include:

- Terraform
- demo controller
- Elastic configuration scripts
- CALDERA integration
- detection tests

A service should only get the permissions it needs.

ex: the demo contrller only gets what it needs to initialize the attack for caldera.

## Demo users

Demo users will be separate from admin users.

They may be allowed to:

- view demo dashboards
- view selected security events
- start ONLY approved simulations
- stat simulation so they can see when finished

They should not be allowed to:

- change Elastic settings
- change detection rules
- access Elastic API keys
- access CALDERA directly
- enter arbitrary commands
- choose arbitrary targets
- access SSH
- change cloud infrastructure

## Human accounts and service accounts

I want to keep these separate.

Human account:

    me
     |
     v
    MFA / YubiKey
     |
     v
    admin access

Service account:

    application
       |
       v
    limited credentials
       |
       v
    only the API access it needs

Demo account:

    demo user
       |
       v
    limited permissions
       |
       v
    demo functions only

## Current administrator authentication

The administrator account uses a YubiKey 5 NFC for Google and GitHub authentication.

Google Cloud administration is performed through the administrator's Google account.

Local Terraform uses Application Default Credentials as the source identity and then impersonates the dedicated Terraform service account.

The YubiKey is for human authentication. Automated workloads do not depend on a physical security key.

## Recovery

Before I require the YubiKey for an important admin account, I need to make
sure I have a recovery method.

I also plan to use a backup hardware key later.

## packer-deployer

Packer uses the same impersonation pattern as Terraform: my local ADC
identity impersonates a dedicated packer-deployer service account, so
Packer builds never run as me directly.

packer-deployer needs permission to create and manage Compute Engine
images, not just create/delete temporary VMs. I gave it a custom role,
packerImageManager, instead of a broad predefined role, since it only
needs:

- compute.images.create
- compute.images.get
- compute.images.list
- compute.images.delete
- compute.images.deprecate
- compute.images.useReadOnly

I found that I needed compute.images.deprecate as Packer tries
to deprecate the previous image in a family every time it builds a new
one, even on the first build. Sans that permission the build
crashed after the image was already created. packerImageManager
is defined in terraform/iam.tf.

To let Terraform manage that role, I also had to grant terraform-deployer
roles/iam.roleAdmin, since it had no IAM permissions before this.
