output "project_name" {
  description = "Human-readable name of the Google Cloud project."
  value       = data.google_project.current.name
}

output "vpc_name" {
  description = "Name of the purple team lab VPC."
  value       = google_compute_network.lab.name
}

output "control_subnet_name" {
  description = "Name of the subnet used by control-side lab systems."
  value       = google_compute_subnetwork.control.name
}

output "target_subnet_name" {
  description = "Name of the subnet used by target lab systems."
  value       = google_compute_subnetwork.target.name
}

output "workstation_subnet_name" {
  description = "Name of the Windows workstation subnet."
  value       = google_compute_subnetwork.workstation.name
}
