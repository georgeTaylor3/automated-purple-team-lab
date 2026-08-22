# variables.pkr.hcl
#
# This declares the environment-specific inputs used by the Windows
# workstation image build.
#
# It intentionally does NOT contain real project-specific values. Those are
# supplied later through an ignored .pkrvars.hcl file.
#
# Keeping the declarations separate from the real values gives us:
#
#   1. a reusable public Packer template;
#   2. local environment-specific configuration;
#   3. a reduced chance of accidentally committing project identifiers;
#   4. future CI/CD integration.

variable "project_id" {
  description = "Google Cloud project in which Packer creates temporary build resources."
  type        = string
}

variable "region" {
  description = "Google Cloud region containing the Packer builder subnet."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone in which Packer creates the temporary Windows builder."
  type        = string
  default     = "us-central1-a"
}

variable "control_subnet" {
  description = "Existing private subnet used for temporary Packer image builders."
  type        = string
  default     = "control-subnet"
}

variable "packer_deployer_service_account" {
  description = "Service account impersonated by Packer when calling Google Cloud APIs."
  type        = string
}

variable "packer_builder_service_account" {
  description = "Runtime service account attached to the temporary Windows builder VM."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type used only while constructing the Windows image."
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size" {
  description = "Temporary Windows boot disk size in GiB."
  type        = number
  default     = 50
}

variable "skip_create_image" {
  description = "If true, exercise the builder lifecycle without creating a permanent custom image."
  type        = bool
  default     = false
}
