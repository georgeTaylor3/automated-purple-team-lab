output "project_name" {
  description = "Human-readable name of the Google Cloud project."
  value       = data.google_project.current.name
}
