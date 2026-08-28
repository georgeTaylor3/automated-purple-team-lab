resource "google_compute_instance" "control_node" {
  depends_on = [
    google_project_iam_member.terraform_deployer_compute_instance_manager
  ]
  name         = "control-node"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-standard-2"

  boot_disk {
    initialize_params {
      image = "projects/${var.project_id}/global/images/family/purple-control-node"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.control.name
    # No access_config block: no external IP, matching every other
    # workload in this lab.
  }

  service_account {
    email  = local.control_node_service_account
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = {
    role = "control-node"
  }
}
