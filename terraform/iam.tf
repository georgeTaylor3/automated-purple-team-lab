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

resource "google_project_iam_custom_role" "terraform_compute_instance_manager" {
  role_id     = "terraformComputeInstanceManager"
  title       = "Terraform Compute Instance Manager"
  description = "Permissions for Terraform to create and manage lab Compute Engine instances."
  project     = var.project_id
  stage       = "GA"

  permissions = [
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setMetadata",
    "compute.instances.setLabels",
    "compute.instances.setServiceAccount",
    "compute.disks.create",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.use",
    "compute.images.useReadOnly",
    "compute.subnetworks.use",
    "compute.subnetworks.get",
    "compute.networks.get",
    "compute.zones.get",
    "compute.machineTypes.get",
    "compute.globalOperations.get",
    "compute.zoneOperations.get",
  ]
}

resource "google_project_iam_member" "terraform_deployer_compute_instance_manager" {
  project = var.project_id
  role    = google_project_iam_custom_role.terraform_compute_instance_manager.id
  member  = "serviceAccount:terraform-deployer@${var.project_id}.iam.gserviceaccount.com"
}
