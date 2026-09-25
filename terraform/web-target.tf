resource "google_compute_instance" "web_target" {
  depends_on = [
    google_project_iam_member.terraform_deployer_compute_instance_manager
  ]

  name         = "web-target"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-medium"

  boot_disk {
    initialize_params {
      image = "projects/${var.project_id}/global/images/family/purple-web-target"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.target.name
    # No access_config block: no external IP, matching every other
    # workload in this lab.
  }

  service_account {
    email  = local.web_target_service_account
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    fleet-url              = "https://10.60.10.39:8220"
    fleet-enrollment-token = var.fleet_enrollment_token_web
    startup-script         = file("${path.module}/../scripts/web-target-setup.sh")
  }

  labels = {
    role = "web-target"
  }
}
