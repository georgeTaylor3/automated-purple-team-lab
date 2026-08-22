locals {
  caldera_control_service_account = "caldera-control-sa@${var.project_id}.iam.gserviceaccount.com"
  web_target_service_account      = "web-target-sa@${var.project_id}.iam.gserviceaccount.com"
  workstation_service_account     = "workstation-target-sa@${var.project_id}.iam.gserviceaccount.com"
  packer_builder_service_account  = "packer-builder-sa@${var.project_id}.iam.gserviceaccount.com"
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

# -----------------------------------------------------------------------------
# Packer Windows image-builder firewall policy
# -----------------------------------------------------------------------------
#
# Packer creates a temporary Windows Server VM while constructing the
# workstation golden image.
#
# The temporary builder:
#
#   - runs with packer-builder-sa as its workload identity;
#   - receives no external IP address;
#   - is reached through Google Identity-Aware Proxy (IAP);
#   - accepts WinRM over HTTPS only from Google's IAP TCP-forwarding range;
#   - may use outbound HTTPS for build-time dependencies;
#   - may reach Google Windows KMS for activation;
#   - is denied other outbound traffic.
#
# The builder is placed in control-subnet. That subnet already has the
# project's Cloud NAT configuration, so no Packer-specific NAT resource is
# required.
#
# These rules are selected by the builder's service-account identity. They
# therefore do not grant the same access to every VM in control-subnet.

resource "google_compute_firewall" "allow_iap_to_packer_winrm" {
  name        = "allow-iap-to-packer-winrm"
  description = "Allow IAP TCP forwarding to temporary Packer Windows builders over WinRM HTTPS."

  network   = google_compute_network.lab.name
  direction = "INGRESS"
  priority  = 900

  # 35.235.240.0/20 is Google's IAP TCP-forwarding source range.
  #
  # It is not one of this lab's VPC subnets. When an authenticated IAP
  # connection is proxied into the VPC, the firewall sees traffic arriving
  # from this Google-managed range.
  source_ranges = [
    "35.235.240.0/20"
  ]

  # Only VMs running with the dedicated temporary Packer runtime identity
  # receive this rule.
  target_service_accounts = [
    local.packer_builder_service_account
  ]

  # 5986 is WinRM over HTTPS. We do not expose unencrypted WinRM on 5985.
  allow {
    protocol = "tcp"
    ports    = ["5986"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_iap_to_packer_ssh" {
  name        = "allow-iap-to-packer-ssh"
  description = "Allow IAP TCP forwarding to temporary Packer Linux builders over SSH."

  network   = google_compute_network.lab.name
  direction = "INGRESS"
  priority  = 900

  source_ranges = [
    "35.235.240.0/20"
  ]

  target_service_accounts = [
    local.packer_builder_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_packer_windows_kms_egress" {
  name        = "allow-packer-windows-kms"
  description = "Allow temporary Windows image builders to reach Google Windows KMS for activation."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 500

  # This is the narrowly scoped Google Windows KMS IPv4 destination used for
  # Windows activation and renewal. The /32 means exactly one IPv4 address.
  destination_ranges = [
    "35.190.247.13/32"
  ]

  target_service_accounts = [
    local.packer_builder_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["1688"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_packer_https_egress" {
  name        = "allow-packer-https-egress"
  description = "Allow temporary Packer builders outbound HTTPS for image-build dependencies."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 2500

  # The initial image build may need to contact multiple Microsoft, package,
  # and software repositories whose destination addresses can change.
  #
  # We therefore permit any IPv4 destination but restrict the connection to
  # TCP 443. This can be tightened later if the dependency destinations become
  # sufficiently predictable or are moved behind an internal artifact source.
  destination_ranges = [
    "0.0.0.0/0"
  ]

  target_service_accounts = [
    local.packer_builder_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_packer_other_egress" {
  name        = "deny-packer-other-egress"
  description = "Deny temporary Packer builder egress that is not explicitly allowed by a higher-priority rule."

  network   = google_compute_network.lab.name
  direction = "EGRESS"
  priority  = 3000

  # This explicit deny prevents the builder from falling through to Google's
  # implied allow-egress behavior for traffic that is not covered by one of
  # the higher-priority Packer allow rules.
  destination_ranges = [
    "0.0.0.0/0"
  ]

  target_service_accounts = [
    local.packer_builder_service_account
  ]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}
