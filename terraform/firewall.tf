locals {
  caldera_control_service_account = "caldera-control-sa@${var.project_id}.iam.gserviceaccount.com"
  purple_target_service_account   = "purple-target-sa@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_compute_firewall" "allow_target_to_caldera_c2_ingress" {
  name        = "allow-target-to-caldera-c2"
  description = "Allow the purple-team target workload to initiate CALDERA C2 traffic on TCP 8888."

  network   = google_compute_network.lab.name
  direction = "INGRESS"
  priority  = 1000

  source_service_accounts = [
    local.purple_target_service_account
  ]

  target_service_accounts = [
    local.caldera_control_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_target_to_caldera_c2_egress" {
  name        = "allow-target-to-caldera-c2-egress"
  description = "Allow the purple-team target workload to send CALDERA C2 traffic to the control subnet on TCP 8888."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = [
    var.control_subnet_cidr
  ]

  target_service_accounts = [
    local.purple_target_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_target_to_control" {
  name        = "deny-target-to-control"
  description = "Deny target-initiated traffic to the control subnet except for explicitly higher-priority rules."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 2000

  destination_ranges = [
    var.control_subnet_cidr
  ]

  target_service_accounts = [
    local.purple_target_service_account
  ]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_caldera_to_target" {
  name        = "deny-caldera-to-target"
  description = "Deny new connections initiated by the CALDERA workload toward the target subnet."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 2000

  destination_ranges = [
    var.target_subnet_cidr
  ]

  target_service_accounts = [
    local.caldera_control_service_account
  ]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}
