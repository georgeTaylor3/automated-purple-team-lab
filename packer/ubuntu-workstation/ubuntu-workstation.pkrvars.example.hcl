# ubuntu-workstation.pkrvars.example.hcl
#
# Public example configuration for the Ubuntu workstation image build.
#
# This file is intended to be committed to the public repository. It contains
# placeholders rather than environment-specific Google Cloud identifiers.
#
# A real local build uses:
#
#   ubuntu-workstation.pkrvars.hcl
#
# That file is excluded from Git.

project_id = "YOUR_GCP_PROJECT_ID"

packer_deployer_service_account = "packer-deployer@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com"
packer_builder_service_account  = "packer-builder-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com"

region = "us-central1"
zone   = "us-central1-a"

control_subnet = "control-subnet"

machine_type = "e2-medium"
disk_size    = 20

# Keep this true for the initial connectivity smoke test.
#
# The temporary Ubuntu builder will be created and provisioned, but Packer
# will not preserve a custom image afterward.
skip_create_image = true
