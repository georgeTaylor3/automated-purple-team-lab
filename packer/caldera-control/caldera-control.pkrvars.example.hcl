# caldera-control.pkrvars.example.hcl
#
# Public example configuration for the CALDERA control image build.
#
# This file is intended to be committed to the public repository. It contains
# placeholders rather than environment-specific Google Cloud identifiers.
#
# A real local build uses:
#
#   caldera-control.pkrvars.hcl
#
# That file is excluded from Git.

project_id = "YOUR_GCP_PROJECT_ID"

packer_deployer_service_account = "packer-deployer@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com"
packer_builder_service_account  = "packer-builder-sa@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com"

region = "us-central1"
zone   = "us-central1-a"

control_subnet = "control-subnet"

machine_type = "e2-medium"
disk_size    = 30

caldera_version = "master"

# Keep this true for the initial connectivity smoke test.
skip_create_image = true
