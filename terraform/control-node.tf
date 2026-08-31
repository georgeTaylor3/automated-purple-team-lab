resource "google_compute_address" "control_node_internal" {
  name         = "control-node-internal"
  region       = var.region
  subnetwork   = google_compute_subnetwork.control.id
  address_type = "INTERNAL"

  description = "Reserved so Fleet Server's advertised URL survives control-node being destroyed and recreated. Already-enrolled agents can't rediscover Fleet Server on their own if the address changes -- a dynamic IP works until the first real recreation after agents exist."
}

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
      size  = 50
      type  = "pd-balanced"
    }
  }

network_interface {
  subnetwork = google_compute_subnetwork.control.name
  network_ip = google_compute_address.control_node_internal.address
  # no external IP
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
