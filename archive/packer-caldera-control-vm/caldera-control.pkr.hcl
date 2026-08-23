# caldera-control.pkr.hcl
#
# Builds the CALDERA control node golden image. Same account and network
# model as the workstation builds -- see docs/08-packer-image-pipeline.md.
#
# Unlike the workstation images, CALDERA does not need a runtime secret to
# start (no enrollment token, no session-specific server address -- it IS
# the server). So its systemd service is baked in enabled, not deferred to
# a boot-time script. Elastic Agent still follows the deferred-enrollment
# pattern, since Fleet enrollment does need a session-specific token.
#
# Identity separation (same as the workstation builds):
#
#     packer-deployer          Google Cloud API identity used by Packer
#     packer-builder-sa        runtime identity attached to the temporary VM
#     caldera-control-sa       NOT used here; belongs to the permanent VM
#                               created later by Terraform.

locals {
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "caldera_control" {
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

  # Packer -> IAP tunnel -> SSH :22, same as the Ubuntu workstation build.
  communicator = "ssh"
  ssh_username = "packer"

  image_name        = "purple-caldera-control-${local.build_timestamp}"
  image_family      = "purple-caldera-control"
  image_description = "CALDERA control node baseline for the automated purple-team lab."

  skip_create_image = var.skip_create_image
}

build {
  name = "caldera-control-image-build"

  sources = [
    "source.googlecompute.caldera_control"
  ]

  # Smoke test: proves Packer reached the VM over IAP + SSH.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'Packer SSH smoke test succeeded.'",
      "grep PRETTY_NAME /etc/os-release"
    ]
  }

  # CALDERA install: OS packages, Go toolchain (pinned -- Ubuntu 24.04's
  # apt package ships Go 1.22, CALDERA wants 1.24+), Node.js (needed for
  # the --build step below), source, and Python deps.
  provisioner "shell" {
    environment_vars = [
      "CALDERA_VERSION=${var.caldera_version}",
      "GO_VERSION=1.27.0"
    ]

    inline = [
      "set -e",
      "sudo apt-get update",

      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv git curl unzip",
      "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs",

      "curl -sSL -o /tmp/go.tar.gz \"https://go.dev/dl/go$${GO_VERSION}.linux-amd64.tar.gz\"",
      "sudo tar -C /usr/local -xzf /tmp/go.tar.gz",
      "rm -f /tmp/go.tar.gz",
      "echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh",

      "sudo git clone --recursive --branch \"$CALDERA_VERSION\" https://github.com/apache/caldera.git /opt/caldera",

      "cd /opt/caldera",
      "sudo python3 -m venv /opt/caldera/venv",
      "sudo /opt/caldera/venv/bin/pip install --upgrade pip",
      "sudo /opt/caldera/venv/bin/pip install -r requirements.txt",

      "echo 'CALDERA source and Python dependencies installed.'"
    ]
  }

  # One-time UI build. The --build flag bundles the VueJS UI (magma
  # plugin) via npm on server startup -- it isn't a separate command, so
  # this starts the server briefly, waits for the build to finish, then
  # stops it. Not yet verified against a real run: the fixed wait time is
  # a first guess, not a confirmed value.
  provisioner "shell" {
    inline = [
      "set -e",
      "export PATH=$PATH:/usr/local/go/bin",
      "cd /opt/caldera",
      "sudo -E env PATH=$PATH /opt/caldera/venv/bin/python3 server.py --insecure --build > /tmp/caldera-build.log 2>&1 &",
      "CALDERA_BUILD_PID=$!",
      "echo \"Waiting for UI build to finish (pid $CALDERA_BUILD_PID)...\"",
      "sleep 90",
      "sudo kill \"$CALDERA_BUILD_PID\" || true",
      "sleep 5",
      "echo 'CALDERA UI build step complete -- check /tmp/caldera-build.log if plugins/dist look incomplete.'",
      "tail -n 40 /tmp/caldera-build.log || true"
    ]
  }

  # systemd unit: baked in and enabled, no --build flag needed on future
  # boots since the UI is already bundled from the step above.
  provisioner "shell" {
    inline = [
      "set -e",
      "cat <<'UNIT' | sudo tee /etc/systemd/system/caldera.service",
      "[Unit]",
      "Description=CALDERA control server",
      "After=network-online.target",
      "Wants=network-online.target",
      "",
      "[Service]",
      "WorkingDirectory=/opt/caldera",
      "Environment=PATH=/usr/local/go/bin:/usr/bin:/bin",
      "ExecStart=/opt/caldera/venv/bin/python3 server.py --insecure",
      "Restart=on-failure",
      "RestartSec=5",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "UNIT",

      "sudo systemctl daemon-reload",
      "sudo systemctl enable caldera.service",

      "echo 'CALDERA systemd service installed and enabled.'"
    ]
  }

  # Elastic Agent: same pattern and version pin as the workstation builds.
  # Binary only -- enrollment needs a Fleet URL and token specific to a
  # running instance, deferred to a boot-time startup script.
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
