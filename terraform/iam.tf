resource "google_project_iam_custom_role" "packer_image_manager" {
  role_id     = "packerImageManager"
  title       = "Packer Image Manager"
  description = "Permissions for Packer to create and manage custom Compute Engine images."
  project     = var.project_id
  stage       = "GA"

  permissions = [
    "compute.images.create",
    "compute.images.get",
    "compute.images.list",
    "compute.images.delete",
    "compute.images.deprecate",
    "compute.images.useReadOnly",
  ]
}

resource "google_project_iam_member" "packer_deployer_image_manager" {
  project = var.project_id
  role    = google_project_iam_custom_role.packer_image_manager.id
  member  = "serviceAccount:packer-deployer@${var.project_id}.iam.gserviceaccount.com"
}
