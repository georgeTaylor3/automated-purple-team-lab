# variables.pkr.hcl
#
# Same variable names as the workstation builds, so all three pipelines
# stay easy to compare. Real values live in an ignored .pkrvars.hcl file.

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
  description = "Google Cloud zone in which Packer creates the temporary CALDERA builder."
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
  description = "Runtime service account attached to the temporary CALDERA builder VM. Same identity used to build the workstation images -- this is a build-time toolchain identity, not the identity CALDERA runs as later."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type used only while constructing the CALDERA image."
  type        = string
  default     = "e2-medium"
}

variable "disk_size" {
  description = "Temporary CALDERA boot disk size in GiB."
  type        = number
  default     = 30
}

variable "caldera_version" {
  description = "CALDERA git ref (tag or branch) to build from."
  type        = string
  default     = "master"
}

variable "skip_create_image" {
  description = "If true, exercise the builder lifecycle without creating a permanent custom image."
  type        = bool
  default     = false
}
