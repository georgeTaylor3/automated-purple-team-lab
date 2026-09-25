#!/usr/bin/env bash
# scripts/set-lab-vars.sh
#
# Populates the shell variables used throughout this project's setup
# commands. Not gitignored -- contains no secrets, just derived/public
# values (project ID, service account emails built from it).
#
# Usage: source this file, don't execute it, so the variables land in
# your current shell rather than a throwaway subshell:
#
#   source scripts/set-lab-vars.sh
 
PROJECT_ID=$(gcloud config get-value project)
export PROJECT_ID
 
PACKER_DEPLOYER_SA="packer-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
export PACKER_DEPLOYER_SA
 
PACKER_BUILDER_SA="packer-builder-sa@${PROJECT_ID}.iam.gserviceaccount.com"
export PACKER_BUILDER_SA
 
TERRAFORM_DEPLOYER_SA="terraform-deployer@${PROJECT_ID}.iam.gserviceaccount.com"
export TERRAFORM_DEPLOYER_SA
 
CONTROL_NODE_SA="control-node-sa@${PROJECT_ID}.iam.gserviceaccount.com"
export CONTROL_NODE_SA
 
MY_ACCOUNT=$(gcloud config get-value account)
export MY_ACCOUNT

CALDERA_RED="$(gcloud secrets versions access latest --secret=caldera-red-password --project="${PROJECT_ID}")"
export CALDERA_RED

echo "Fetching TF_VAR_fleet_enrollment_token_workstation from Secret Manager..."
TF_VAR_fleet_enrollment_token_workstation=$(gcloud secrets versions access latest --secret=linux-workstation-target-fleet-enrollment-token --project="$PROJECT_ID" 2>/dev/null || echo "")
export TF_VAR_fleet_enrollment_token_workstation

echo "Fetching TF_VAR_fleet_enrollment_token_web from Secret Manager..."
TF_VAR_fleet_enrollment_token_web=$(gcloud secrets versions access latest --secret=linux-webserver-target-fleet-enrollment-token --project="$PROJECT_ID" 2>/dev/null || echo "")
export TF_VAR_fleet_enrollment_token_web

echo "Fetching TF_VAR_billing_account_id from Secret Manager..."
TF_VAR_billing_account_id=$(gcloud secrets versions access latest --secret=billing-account-id --project="$PROJECT_ID" 2>/dev/null || echo "")
export TF_VAR_billing_account_id

echo "PROJECT_ID..............done"
echo "PACKER_DEPLOYER_SA......done"
echo "PACKER_BUILDER_SA.......done"
echo "TERRAFORM_DEPLOYER_SA...done"
echo "CONTROL_NODE_SA.........done"
echo "CALDERA_RED.............done"
echo "MY_ACCOUNT..............done"
echo "TF_VAR_billing_account_id=$([ -n "$TF_VAR_billing_account_id" ] && echo '(set)' || echo '(NOT SET -- secret missing or inaccessible)')"
echo "TF_VAR_fleet_enrollment_token_workstation=$([ -n "$TF_VAR_fleet_enrollment_token_workstation" ] && echo '(set)' || echo '(NOT SET -- secret missing or inaccessible)')"
echo "TF_VAR_fleet_enrollment_token_web=$([ -n "$TF_VAR_fleet_enrollment_token_web" ] && echo '(set)' || echo '(NOT SET -- secret missing or inaccessible)')"

