resource "google_compute_router" "lab" {
  name    = "purple-team-router"
  region  = var.region
  network = google_compute_network.lab.id
}

resource "google_compute_router_nat" "control" {
  name   = "control-cloud-nat"
  router = google_compute_router.lab.name
  region = google_compute_router.lab.region

  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.control.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
