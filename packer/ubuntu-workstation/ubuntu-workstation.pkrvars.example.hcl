# ubuntu-workstation.pkrvars.example.hcl
#
# Public example configuration for the Ubuntu workstation image build.
#
# project_id, both service account emails, and control_subnet are no
# longer set here -- see scripts/generate-shared-vars.sh.
#
# A real local build uses:
#
#   ubuntu-workstation.pkrvars.hcl
#
# That file is excluded from Git.

region = "us-central1"
zone   = "us-central1-a"

machine_type = "e2-medium"
disk_size    = 20

skip_create_image = true
