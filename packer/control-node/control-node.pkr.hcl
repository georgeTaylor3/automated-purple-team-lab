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

  # Swap file. Elasticsearch + Kibana + CALDERA running together on a
  # modest instance can exhaust RAM under real load -- confirmed the
  # hard way on 2026-08-28, where a fully-idle e2-medium (4GB) was
  # already sitting at 3.8Gi/3.8Gi used with 105Mi free, no swap,
  # causing even basic SSH/sudo commands to hang or fail with DNS
  # resolution errors under the pressure. This costs 2GB of disk and
  # does nothing when memory isn't under pressure -- it only matters
  # the one time it's actually needed, turning a hard OOM-kill crash
  # into graceful degradation instead. Baked in regardless of instance
  # size, since Elasticsearch in particular tends to grow to fill
  # whatever's available if not explicitly capped.
  provisioner "shell" {
    inline = [
      "set -e",
      "sudo fallocate -l 2G /swapfile",
      "sudo chmod 600 /swapfile",
      "sudo mkswap /swapfile",
      "sudo swapon /swapfile",
      "echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab",
      "free -h",
      "echo 'Swap file created and enabled at boot.'"
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
      "KIBANA_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret=kibana-encryption-key)",
      "cat > \"$REPO_DIR/.env\" <<ENVFILE",
      "ELASTIC_PASSWORD=$ELASTIC_PASSWORD",
      "KIBANA_SYSTEM_PASSWORD=$KIBANA_SYSTEM_PASSWORD",
      "KIBANA_ENCRYPTION_KEY=$KIBANA_ENCRYPTION_KEY",
      "ENVFILE",
      "chmod 600 \"$REPO_DIR/.env\"",
      "",
      "docker compose up -d elasticsearch",
      "",
      "echo \"Waiting for Elasticsearch to accept requests...\"",
      "for i in $(seq 1 30); do",
      "  if curl -s -o /dev/null -u \"elastic:$ELASTIC_PASSWORD\" http://localhost:9200; then",
      "    break",
      "  fi",
      "  sleep 5",
      "done",
      "",
      "echo \"Syncing kibana_system password (needed every time Elasticsearch's data volume starts fresh -- setting ELASTICSEARCH_PASSWORD in Kibana's environment does not itself change the password Elasticsearch expects)...\"",
      "curl -s -u \"elastic:$ELASTIC_PASSWORD\" -X POST \"http://localhost:9200/_security/user/kibana_system/_password\" \\",
      "  -H \"Content-Type: application/json\" \\",
      "  -d \"{\\\"password\\\":\\\"$KIBANA_SYSTEM_PASSWORD\\\"}\"",
      "echo",
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
      "docker compose up -d elasticsearch kibana caldera",
      "echo \"purple-lab-deploy.sh complete (fleet-server held back until a real Fleet Server service token exists -- see docs/02-identity-and-access.md).\"",
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
