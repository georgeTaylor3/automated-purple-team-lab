resource "google_compute_network" "lab" {
  name                    = "purple-team-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "control_node" {
  name                     = "control-node-subnet"
  ip_cidr_range            = var.control_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.lab.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "web_target" {
  name                     = "web-target-subnet"
  ip_cidr_range            = var.target_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.lab.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "linux_workstation_target" {
  name                     = "linux-workstation-target-subnet"
  ip_cidr_range            = var.workstation_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.lab.id
  private_ip_google_access = true
}
