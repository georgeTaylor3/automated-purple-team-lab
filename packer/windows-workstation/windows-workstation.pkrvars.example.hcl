# windows-workstation.pkrvars.example.hcl
#
# Public example configuration for the Windows workstation image build.
#
# project_id, both service account emails, and control_subnet are no
# longer set here -- they're generated from Terraform outputs into
# shared/lab-vars.json (see scripts/generate-shared-vars.sh) and passed
# as a separate -var-file, since the same values are used by all three
# Packer pipelines.
#
# A real local build uses:
#
#   windows-workstation.pkrvars.hcl
#
# That file is excluded from Git.

region = "us-central1"
zone   = "us-central1-a"

machine_type = "e2-standard-2"
disk_size    = 50

skip_create_image = true
