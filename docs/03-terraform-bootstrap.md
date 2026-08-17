# Terraform bootstrap

Terraform manages Google Cloud (GC) infrastructure for this project.

## Local authentication

Local Terraform runs start with Google Application Default Credentials (ADC) for the administrator's Google account.

The administrator account uses multi factor authentication (MFA) in the form a hardware security key (Yubikey 5 NFc in this project). It is phising resintant and conveniant to use.

## Terraform service account

Normal Terraform provider operations use a dedicated service account named `terraform-deployer`.

The administrator is allowed to impersonate that service account.

The impersonation permission is granted on the Terraform service account itself instead of across all service accounts in the project. My admin credentials are ONLY limited to impersonating the terrafor-deployer user, not ALL service accounts. 

This also alows for the use of short-lived credentials rather than a persistant secret key json stored locally.

## Current permissions

The Terraform service account starts with read-only access needed to verify the project. i define the API resources th
at terraform is allowed to call (right now need GC project get), and IAM handles what resource/object the user is allo
wed to interact with.

More permissions will be added only when needed. I only want to add what it needs when it needs rather than loading th
e user with all the permissions it needs from the start.

The service account is not given Owner or Editor.

## Local files

The real `terraform.tfvars` file stays local and is ignored by Git va git/<projectname>/.gitignore.

Terraform state files and the `.terraform/` working directory are also ignored.

The `.terraform.lock.hcl` provider lock file is committed.

## Bootstrap boundary

The initial Terraform service account and impersonation permissions were created outside the main Terraform configuration.

This solves the bootstrap problem: Terraform needs an identity before it can use that identity to manage infrastructure.

The main Terraform configuration then impersonates the dedicated service account instead of running directly with the administrator's project permissions.

So... GC > ADC > My admin account > allowed to imporsonate > terraform-deployer > that can call project get (currently)

## Future automation

GitHub Actions will not use a downloaded Google service account key.

The planned CI authentication method is Workload Identity Federation with short-lived credentials. for now thats the plan.
