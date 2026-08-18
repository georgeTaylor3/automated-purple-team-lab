resource "google_compute_network" "lab" {
  name                    = "purple-team-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "control" {
  name                     = "control-subnet"
  ip_cidr_range            = var.control_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.lab.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "target" {
  name                     = "target-subnet"
  ip_cidr_range            = var.target_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.lab.id
  private_ip_google_access = true
}
