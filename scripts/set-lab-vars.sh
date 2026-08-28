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

echo "PROJECT_ID=$PROJECT_ID"
echo "PACKER_DEPLOYER_SA=$PACKER_DEPLOYER_SA"
echo "PACKER_BUILDER_SA=$PACKER_BUILDER_SA"
echo "TERRAFORM_DEPLOYER_SA=$TERRAFORM_DEPLOYER_SA"
echo "CONTROL_NODE_SA=$CONTROL_NODE_SA"
echo "MY_ACCOUNT=$MY_ACCOUNT"
