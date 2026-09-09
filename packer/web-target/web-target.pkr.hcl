# web-target.pkr.hcl
#
# Builds the web-target golden image: a genuinely separate image from
# purple-ubuntu-workstation, representing the "simulated business web
# service" role, not the workstation-comparison role. Same underlying
# Ubuntu, deliberately kept as its own image family so the role
# distinction in docs/05-firewall-trust-model.md (web-target-sa vs
# workstation-target-sa) stays real, not just a label on shared bits.
#
# nginx itself and the Elastic Agent binary are baked in (static,
# belong in the image). The TLS certificate is generated fresh at
# boot time, not baked in -- baking a private key into a golden image
# would mean every instance from this image shares the identical
# key, a real, avoidable weakness. Same install/configure split used
# everywhere else in this project.
#
# Identity separation (same as the other pipelines):
#
#     packer-deployer          Google Cloud API identity used by Packer
#     packer-builder-sa        runtime identity attached to the temporary VM
#     web-target-sa            NOT used here; belongs to the permanent VM
#                               created later by Terraform.

locals {
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "web_target" {
  project_id = var.project_id

  impersonate_service_account = var.packer_deployer_service_account

  source_image_family     = "ubuntu-2404-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]

  region             = var.region
  zone               = var.zone
  subnetwork         = var.control_subnet
  network_project_id = var.project_id

  machine_type = var.machine_type
  disk_size    = var.disk_size
  disk_type    = "pd-balanced"

  omit_external_ip = true
  use_internal_ip  = true
  use_iap          = true

  service_account_email = var.packer_builder_service_account

  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]

  enable_secure_boot          = true
  enable_vtpm                 = true
  enable_integrity_monitoring = true

  communicator = "ssh"
  ssh_username = "packer"

  image_name        = "purple-web-target-${local.build_timestamp}"
  image_family      = "purple-web-target"
  image_description = "Web-target (simulated business web service) baseline for the automated purple-team lab. Genuinely separate image from purple-ubuntu-workstation, representing a distinct role even though both are Ubuntu."

  skip_create_image = var.skip_create_image
}

build {
  name = "web-target-image-build"

  sources = [
    "source.googlecompute.web_target"
  ]

  # Smoke test.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'Packer SSH smoke test succeeded.'",
      "grep PRETTY_NAME /etc/os-release"
    ]
  }

  # nginx: package only. Config/cert generation deferred to boot time
  # (see web-target-setup.sh) -- a self-signed cert baked into the
  # image would mean every instance shares the identical private key.
  provisioner "shell" {
    inline = [
      "set -e",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx openssl",
      "sudo systemctl disable nginx",
      "echo 'nginx package installed, left disabled until boot-time cert generation and config.'"
    ]
  }

  # Docker + Juice Shop image, baked in at build time. Juice Shop
  # itself needs no per-instance secret/config, unlike nginx's TLS
  # cert -- safe to bake the image in directly, just start it fresh
  # at boot (see web-target-setup.sh). Pinned version, same discipline
  # as every other tool in this project.
  provisioner "shell" {
    inline = [
      "set -e",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \\\"$VERSION_CODENAME\\\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io",
      "sudo docker pull bkimminich/juice-shop:v20.1.1",
      "echo 'Docker installed, Juice Shop image pulled and baked in.'"
    ]
  }

  # Elastic Agent: same pattern and version pin as the other target
  # images. Binary only -- enrollment needs a Fleet URL and token
  # specific to a running instance, deferred to a boot-time script.
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
