# variables.pkr.hcl
#
# Same variable naming pattern as the other pipelines. Real values live
# in an ignored .pkrvars.hcl file, or in shared/lab-vars.json.

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
  description = "Google Cloud zone in which Packer creates the temporary control-node builder."
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
  description = "Runtime service account attached to the temporary control-node builder VM. Build-time toolchain identity only -- not the identity control-node runs as later."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type used only while constructing the control-node image."
  type        = string
  default     = "e2-medium"
}

variable "disk_size" {
  description = "Temporary control-node boot disk size in GiB."
  type        = number
  default     = 20
}

variable "repo_url" {
  description = "Public git URL of this repository, cloned onto control-node at boot."
  type        = string
  default     = "https://github.com/YOUR_USERNAME/automated-purple-team-lab.git"
}

variable "skip_create_image" {
  description = "If true, exercise the builder lifecycle without creating a permanent custom image."
  type        = bool
  default     = false
}
