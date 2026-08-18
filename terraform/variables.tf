variable "project_id" {
  description = "Google Cloud project ID used by the purple team lab."
  type        = string
}

variable "region" {
  description = "Default Google Cloud region for lab resources."
  type        = string
  default     = "us-central1"
}

variable "terraform_service_account" {
  description = "Service account Terraform impersonates when managing Google Cloud resources."
  type        = string
}

variable "control_subnet_cidr" {
  description = "IPv4 CIDR range used by the control subnet."
  type        = string
  default     = "10.60.10.0/24"
}

variable "target_subnet_cidr" {
  description = "IPv4 CIDR range used by the target subnet."
  type        = string
  default     = "10.60.20.0/24"
}
