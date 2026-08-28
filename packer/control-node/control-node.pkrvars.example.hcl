# control-node.pkrvars.example.hcl
#
# Public example configuration for the control-node image build.
#
# A real local build uses:
#
#   control-node.pkrvars.hcl
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

repo_url = "https://github.com/YOUR_USERNAME/automated-purple-team-lab.git"

# Keep this true for the initial connectivity smoke test.
skip_create_image = true
