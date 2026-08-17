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
