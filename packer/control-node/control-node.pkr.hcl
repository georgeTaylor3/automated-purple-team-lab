# control-node.pkr.hcl
#
# Builds the control-node golden image. Unlike the earlier
# purple-caldera-control VM image (now archived), this image does NOT
# bake CALDERA in directly -- CALDERA now runs as a container, defined
# in docker/caldera/Dockerfile and orchestrated by docker-compose.yml
# at the repo root, alongside Elasticsearch and Kibana.
#
# This image's job is narrow and should barely need to change over
# time: install Docker, install git, and bake in a systemd service +
# timer that pulls this repo and refreshes the container stack.
#
# Two separate refresh cadences, deliberately not the same thing:
#
#   - This image (Docker/git/OS) changes rarely. Rebuild it manually
#     or on a slow cadence (monthly is plenty) -- it's not wired to
#     any automatic schedule here.
#   - The container stack refreshes on a much tighter, cheap schedule
#     (the timer below), because the deploy script only pays the real
#     rebuild cost (CALDERA's UI compile, ~6-8 min) when the repo's
#     HEAD commit actually changed since the last successful build.
#     Otherwise it's just `git pull` (usually a no-op) + `docker
#     compose up -d`, which is fast since nothing needs rebuilding.
#
# Identity separation (same as the other pipelines):
#
#     packer-deployer          Google Cloud API identity used by Packer
#     packer-builder-sa        runtime identity attached to the temporary VM
#     control-node-sa          NOT used here; belongs to the permanent VM
#                               created later by Terraform.

locals {
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "control_node" {
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

  image_name        = "purple-control-node-${local.build_timestamp}"
  image_family      = "purple-control-node"
  image_description = "Control node baseline (Docker + git) for the automated purple-team lab. Application stack (CALDERA/Elastic/Kibana) runs as containers, pulled fresh at boot from the repo -- not baked into this image."

  skip_create_image = var.skip_create_image
}

build {
  name = "control-node-image-build"

  sources = [
    "source.googlecompute.control_node"
  ]

  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'Packer SSH smoke test succeeded.'",
      "grep PRETTY_NAME /etc/os-release"
    ]
  }

  provisioner "shell" {
    inline = [
      "set -e",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg git",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \\\"$VERSION_CODENAME\\\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "sudo usermod -aG docker packer",
      "docker --version",
      "docker compose version",
      "echo 'Docker and Compose installed.'"
    ]
  }

  provisioner "shell" {

    inline = [
      "set -e",
      "sudo mkdir -p /opt/purple-lab",

      "cat <<'SCRIPT' | sudo tee /usr/local/bin/purple-lab-deploy.sh",
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      "REPO_DIR=/opt/purple-lab",
      "REPO_URL=\"${var.repo_url}\"",
      "MARKER_FILE=\"$REPO_DIR/.last-built-commit\"",
      "",
      "if [ -d \"$REPO_DIR/.git\" ]; then",
      "  echo \"Repo exists, pulling latest...\"",
      "  cd \"$REPO_DIR\"",
      "  git pull",
      "else",
      "  echo \"Cloning $REPO_URL...\"",
      "  git clone \"$REPO_URL\" \"$REPO_DIR\"",
      "  cd \"$REPO_DIR\"",
      "fi",
      "",
      "echo \"Fetching secrets from Secret Manager...\"",
      "ELASTIC_PASSWORD=$(gcloud secrets versions access latest --secret=elastic-password)",
      "KIBANA_SYSTEM_PASSWORD=$(gcloud secrets versions access latest --secret=kibana-system-password)",
      "cat > \"$REPO_DIR/.env\" <<ENVFILE",
      "ELASTIC_PASSWORD=$ELASTIC_PASSWORD",
      "KIBANA_SYSTEM_PASSWORD=$KIBANA_SYSTEM_PASSWORD",
      "ENVFILE",
      "chmod 600 \"$REPO_DIR/.env\"",
      "",
      "CURRENT_COMMIT=$(git rev-parse HEAD)",
      "LAST_BUILT_COMMIT=\"\"",
      "if [ -f \"$MARKER_FILE\" ]; then",
      "  LAST_BUILT_COMMIT=$(cat \"$MARKER_FILE\")",
      "fi",
      "",
      "if [ \"$CURRENT_COMMIT\" != \"$LAST_BUILT_COMMIT\" ]; then",
      "  echo \"New commit detected ($CURRENT_COMMIT), rebuilding...\"",
      "  docker compose build",
      "  echo \"$CURRENT_COMMIT\" > \"$MARKER_FILE\"",
      "else",
      "  echo \"No changes since last build ($CURRENT_COMMIT), skipping rebuild.\"",
      "fi",
      "",
      "docker compose up -d",
      "echo \"purple-lab-deploy.sh complete.\"",
      "SCRIPT",

      "sudo chmod +x /usr/local/bin/purple-lab-deploy.sh",

      "cat <<'UNIT' | sudo tee /etc/systemd/system/purple-lab-deploy.service",
      "[Unit]",
      "Description=Pull the purple-team-lab repo and refresh the control-node stack",
      "After=docker.service network-online.target",
      "Requires=docker.service",
      "",
      "[Service]",
      "Type=oneshot",
      "User=root",
      "ExecStart=/usr/local/bin/purple-lab-deploy.sh",
      "UNIT",

      "cat <<'TIMER' | sudo tee /etc/systemd/system/purple-lab-deploy.timer",
      "[Unit]",
      "Description=Recurring refresh of the control-node stack (cheap no-op unless something changed)",
      "",
      "[Timer]",
      "OnBootSec=2min",
      "OnCalendar=daily",
      "Persistent=true",
      "",
      "[Install]",
      "WantedBy=timers.target",
      "TIMER",

      "sudo systemctl daemon-reload",
      "sudo systemctl enable purple-lab-deploy.timer",

      "echo 'Deploy service and daily timer installed and enabled.'"
    ]
  }
}
