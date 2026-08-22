#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

terraform output -json | jq '{
  project_id: .project_id.value,
  region: "us-central1",
  zone: "us-central1-a",
  control_subnet: .control_subnet_name.value,
  target_subnet: .target_subnet_name.value,
  workstation_subnet: .workstation_subnet_name.value,
  vpc_name: .vpc_name.value,
  packer_deployer_service_account: (.project_id.value | "packer-deployer@\(.).iam.gserviceaccount.com"),
  packer_builder_service_account: .packer_builder_service_account.value
}' > ../shared/lab-vars.json

echo "Wrote shared/lab-vars.json"
