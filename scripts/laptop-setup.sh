#!/usr/bin/env bash
# scripts/laptop-setup.sh
#
# Bootstraps a fresh laptop for this project. Installs required tooling,
# then reconstructs everything that's gitignored (real Packer vars, the
# local .env for docker-compose) from sources that are ALREADY set up to
# make this possible: Secret Manager for real secrets, and the trimmed
# .pkrvars.example.hcl files (which no longer contain anything secret --
# project_id/service-account values now come from shared/lab-vars.json).
#
# What this does NOT do, and why:
#   - gcloud auth login / application-default login: interactive browser
#     flows, can't be scripted.
#   - YubiKey SSH signing key setup: if the key is resident, run
#     `ssh-keygen -K` with the key plugged in to pull it from the
#     hardware directly. If not resident, the stub file needs to be
#     securely copied from the old laptop -- this script can't do that
#     for you.
#   - Docker install itself is included below (apt), but any local
#     docker-compose data (elasticsearch-data, caldera-data volumes)
#     from the old laptop does NOT transfer -- this is fine, since local
#     testing is meant to be disposable, not the source of truth (the
#     real control-node deployment in GCP is unaffected by any of this).
#
# Usage: run from the repo root, after cloning.
#   git clone <repo-url> automated-purple-team-lab
#   cd automated-purple-team-lab
#   ./scripts/laptop-setup.sh

set -euo pipefail

echo "=== 1. Installing base tooling (apt) ==="
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl jq gnupg ca-certificates unzip

echo
echo "=== 2. Installing Docker ==="
if ! command -v docker >/dev/null 2>&1; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "Docker installed. You'll need to log out/in (or run 'newgrp docker') for group membership to take effect."
else
  echo "Docker already installed, skipping."
fi

echo
echo "=== 3. Installing gcloud CLI ==="
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not found. Install it manually from:"
  echo "  https://cloud.google.com/sdk/docs/install"
  echo "(Uses its own installer, not a simple apt package -- re-run this script after installing.)"
  exit 1
else
  echo "gcloud already installed, skipping."
fi

echo
echo "=== 4. Installing Terraform ==="
if ! command -v terraform >/dev/null 2>&1; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update
  sudo apt-get install -y terraform
else
  echo "Terraform already installed, skipping."
fi

echo
echo "=== 5. Installing Packer ==="
if ! command -v packer >/dev/null 2>&1; then
  sudo apt-get install -y packer
else
  echo "Packer already installed, skipping."
fi

echo
echo "=== 6. gcloud authentication (interactive -- can't be automated) ==="
echo "Run these now if you haven't already:"
echo "  gcloud auth login"
echo "  gcloud auth application-default login"
echo "  gcloud config set project purple-lab-48271"
read -r -p "Press enter once you've completed gcloud auth login and application-default login... "

PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
  echo "ERROR: no project set. Run 'gcloud config set project purple-lab-48271' and re-run this script."
  exit 1
fi
echo "Using project: $PROJECT_ID"

echo
echo "=== 7. Regenerating shared/lab-vars.json from Terraform outputs ==="
./scripts/generate-shared-vars.sh

echo
echo "=== 8. Recreating real Packer vars files from the committed examples ==="
echo "(Safe -- these no longer contain project_id or service account values;"
echo " those come from shared/lab-vars.json as a second -var-file.)"
for dir in packer/windows-workstation packer/ubuntu-workstation packer/caldera-control packer/control-node; do
  if [ -d "$dir" ]; then
    example_file=$(find "$dir" -maxdepth 1 -name "*.pkrvars.example.hcl" | head -n 1)
    if [ -n "$example_file" ]; then
      real_file="${example_file%.example.hcl}.hcl"
      if [ ! -f "$real_file" ]; then
        cp "$example_file" "$real_file"
        echo "  Created $real_file"
      else
        echo "  $real_file already exists, skipping."
      fi
    fi
  fi
done

echo
echo "=== 9. Fetching real secrets from Secret Manager into local .env ==="
if [ -f .env ]; then
  echo ".env already exists, skipping (delete it first if you want to regenerate)."
else
  ELASTIC_PASSWORD=$(gcloud secrets versions access latest --secret=elastic-password --project="$PROJECT_ID")
  KIBANA_SYSTEM_PASSWORD=$(gcloud secrets versions access latest --secret=kibana-system-password --project="$PROJECT_ID")
  KIBANA_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret=kibana-encryption-key --project="$PROJECT_ID")

  cat > .env <<EOF
ELASTIC_PASSWORD=$ELASTIC_PASSWORD
KIBANA_SYSTEM_PASSWORD=$KIBANA_SYSTEM_PASSWORD
KIBANA_ENCRYPTION_KEY=$KIBANA_ENCRYPTION_KEY
EOF
  chmod 600 .env
  echo "  Wrote .env from Secret Manager."
fi

echo
echo "=== 10. Setting up lab shell variables ==="
echo "Add this to your shell profile (~/.bashrc or ~/.zshrc) so it's always available:"
echo "  source $(pwd)/scripts/set-lab-vars.sh"
source scripts/set-lab-vars.sh

echo
echo "=== Setup mostly complete. Remaining manual steps: ==="
echo "1. Git SSH signing key: run 'ssh-keygen -K' with your YubiKey plugged in"
echo "   if the key is resident, or securely copy the stub key file from"
echo "   your old laptop if not."
echo "2. Confirm git config recognizes the key:"
echo "     git config --get user.signingkey"
echo "     git config --get gpg.format"
echo "     git config --get gpg.ssh.allowedSignersFile"
echo "3. Log out/in (or 'newgrp docker') if Docker was freshly installed."
echo "4. Test: docker compose up -d   (local stack, separate from real control-node)"
