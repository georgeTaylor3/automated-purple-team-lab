# ubuntu-workstation.pkr.hcl
#
# Builds the Linux workstation-target golden image. Same structure and
# identity model as windows-workstation.pkr.hcl, using SSH over IAP instead
# of WinRM.
#
# skip_create_image defaults to false: a normal build produces a persistent
# custom image. Set skip_create_image=true to exercise the builder lifecycle
# (IAM, networking, IAP, SSH, cleanup) without creating an image artifact.
#
# Identity separation (same as Windows):
#
#     packer-deployer          Google Cloud API identity used by Packer
#     packer-builder-sa        runtime identity attached to the temporary VM
#     linux-workstation-target-sa   NOT used here; belongs to the permanent
#                                    VM created later by Terraform.

locals {
  # GCE custom image names must be unique.
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "ubuntu_workstation" {
  # Google Cloud identity: start as the human operator, then impersonate
  # packer-deployer for short-lived API credentials.
  project_id = var.project_id

  impersonate_service_account = var.packer_deployer_service_account

  # Base operating system: Ubuntu's maintained LTS image family, so future
  # builds automatically pick up the current non-deprecated image.
  source_image_family = "ubuntu-2404-lts-amd64"

  source_image_project_id = [
    "ubuntu-os-cloud"
  ]

  # Temporary builder location: same control-subnet as the Windows builder,
  # for the same reasons (existing Cloud NAT, existing firewall policy).
  region             = var.region
  zone               = var.zone
  subnetwork         = var.control_subnet
  network_project_id = var.project_id

  machine_type = var.machine_type
  disk_size    = var.disk_size
  disk_type    = "pd-balanced"

  # Private networking: no external IP, reached only through an IAP tunnel.
  omit_external_ip = true
  use_internal_ip  = true
  use_iap          = true

  # Builder runtime identity, deliberately separate from packer-deployer.
  service_account_email = var.packer_builder_service_account

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]

  # Shielded VM features.
  enable_secure_boot          = true
  enable_vtpm                 = true
  enable_integrity_monitoring = true

  # Packer communicator: Ubuntu's SSH server is ready shortly after boot, no
  # WinRM-style bootstrap script or wait needed.
  #
  #     Packer -> IAP tunnel -> SSH :22
  communicator = "ssh"
  ssh_username = "packer"

  # Resulting image.
  image_name = "purple-ubuntu-workstation-${local.build_timestamp}"

  image_family = "purple-ubuntu-workstation"

  image_description = "Ubuntu 24.04 LTS workstation-style baseline for the automated purple-team lab."

  skip_create_image = var.skip_create_image
}

build {
  name = "ubuntu-workstation-image-build"

  sources = [
    "source.googlecompute.ubuntu_workstation"
  ]

  # Smoke test: proves Packer reached the VM over IAP + SSH and can run
  # commands. No persistent configuration change.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'Packer SSH smoke test succeeded.'",
      "grep PRETTY_NAME /etc/os-release",
      "echo \"Hostname: $(hostname)\""
    ]
  }

  # Elastic Agent: install the binary only. Enrollment needs a Fleet URL and
  # token specific to a running instance, so it's deferred to a boot-time
  # startup script, same split used for Windows.
  provisioner "shell" {
    environment_vars = [
      "ELASTIC_AGENT_VERSION=8.15.3"
    ]

    inline = [
      "set -e",
      "echo \"Installing Elastic Agent version $ELASTIC_AGENT_VERSION\"",
      "curl -sSL -o /tmp/elastic-agent.tar.gz \"https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$${ELASTIC_AGENT_VERSION}-linux-x86_64.tar.gz\"",
      "tar xzf /tmp/elastic-agent.tar.gz -C /tmp",
      "sudo mkdir -p /opt/elastic",
      "sudo mv \"/tmp/elastic-agent-$${ELASTIC_AGENT_VERSION}-linux-x86_64\" /opt/elastic/elastic-agent",
      "rm -f /tmp/elastic-agent.tar.gz",
      "echo 'Elastic Agent binary installed. Enrollment deferred to boot-time startup script.'"
    ]
  }
}
