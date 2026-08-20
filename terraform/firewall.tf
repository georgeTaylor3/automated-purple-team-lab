locals {
  caldera_control_service_account = "caldera-control-sa@${var.project_id}.iam.gserviceaccount.com"
  web_target_service_account      = "web-target-sa@${var.project_id}.iam.gserviceaccount.com"
  workstation_service_account     = "workstation-target-sa@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_compute_firewall" "allow_target_to_caldera_c2_ingress" {
  name        = "allow-target-to-caldera-c2"
  description = "Allow the purple-team target workloads to initiate CALDERA C2 traffic on TCP 8888."

  network   = google_compute_network.lab.name
  direction = "INGRESS"
  priority  = 1000

  source_service_accounts = [
    local.web_target_service_account,
    local.workstation_service_account
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
  description = "Allow the purple-team target workloads to send CALDERA C2 traffic to the control subnet on TCP 8888."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = [
    var.control_subnet_cidr
  ]

  target_service_accounts = [
    local.web_target_service_account,
    local.workstation_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_workstation_to_web_https_ingress" {
  name        = "allow-workstation-to-web-https"
  description = "Allow the Windows workstation workload to access the Linux web workload over HTTPS."

  network   = google_compute_network.lab.name
  direction = "INGRESS"
  priority  = 1200

  source_service_accounts = [
    local.workstation_service_account
  ]

  target_service_accounts = [
    local.web_target_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_workstation_to_web_https_egress" {
  name        = "allow-workstation-to-web-https-egress"
  description = "Allow the Windows workstation workload to initiate HTTPS traffic to the server target subnet."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 1200

  destination_ranges = [
    var.target_subnet_cidr
  ]

  target_service_accounts = [
    local.workstation_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_workstation_windows_kms_egress" {
  name        = "allow-workstation-windows-kms"
  description = "Allow the Windows workstation workload to reach Google Windows KMS for activation and renewal."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 500

  destination_ranges = [
    "35.190.247.13/32"
  ]

  target_service_accounts = [
    local.workstation_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["1688"]
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
    local.web_target_service_account,
    local.workstation_service_account
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
  description = "Deny new connections initiated by the CALDERA workload toward the target subnets."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 2000

  destination_ranges = [
    var.target_subnet_cidr,
    var.workstation_subnet_cidr
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

resource "google_compute_firewall" "allow_caldera_https_egress" {
  name        = "allow-caldera-https-egress"
  description = "Allow the CALDERA control workload outbound HTTPS for provisioning, updates, and required dependencies."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 2500

  destination_ranges = [
    "0.0.0.0/0"
  ]

  target_service_accounts = [
    local.caldera_control_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_caldera_other_egress" {
  name        = "deny-caldera-other-egress"
  description = "Deny CALDERA control workload egress that is not explicitly allowed by a higher-priority rule."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 3000

  destination_ranges = [
    "0.0.0.0/0"
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

resource "google_compute_firewall" "deny_target_other_egress" {
  name        = "deny-target-other-egress"
  description = "Deny target workload egress that is not explicitly allowed by a higher-priority rule."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 3000

  destination_ranges = [
    "0.0.0.0/0"
  ]

  target_service_accounts = [
    local.web_target_service_account,
    local.workstation_service_account
  ]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}
