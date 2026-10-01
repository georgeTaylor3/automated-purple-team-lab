resource "google_compute_router" "lab" {
  name    = "purple-team-router"
  region  = var.region
  network = google_compute_network.lab.id
}

# control-cloud-nat references google_compute_subnetwork.control_node
# by resource ID -- a genuine, structural circular dependency if that
# subnet's CIDR or identity ever needs to change. Confirmed firsthand
# across two separate sessions (subnet rename, then a CIDR revert):
# the subnet can't be destroyed while NAT still references it, NAT
# can't update away from a subnet that still exists, and Terraform
# cannot reliably sequence around this through -target or -replace
# alone, even when both resources are explicitly listed together --
# targeted resources aren't guaranteed to apply in the order given.
#
# The working fix, when this subnet needs to change again: break the
# cycle OUTSIDE Terraform first, temporarily, via gcloud --
#   gcloud compute routers nats update control-cloud-nat \
#     --router=purple-team-router --region=us-central1 \
#     --project=<PROJECT_ID> --nat-all-subnet-ip-ranges
# This detaches NAT from any specific subnet reference, letting the
# subnet destroy/recreate cleanly through a normal, untargeted
# terraform apply. Afterward, a second, ordinary terraform apply
# (no flags) reconciles NAT back to this file's own declared,
# specifically-scoped configuration -- genuinely safe at that point,
# since the subnet it's repointing to already exists.
resource "google_compute_router_nat" "control" {
  name   = "control-cloud-nat"
  router = google_compute_router.lab.name
  region = google_compute_router.lab.region

  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.control_node.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
