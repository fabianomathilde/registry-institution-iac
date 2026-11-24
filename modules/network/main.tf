# VPC for the environment:
# - one regional subnet for GKE with secondary ranges for pods and services, with Private Google
#   Access (nodes without public IPs still reach Google APIs and Artifact Registry)
# - optional Cloud Router + Cloud NAT, only needed to pull public images (e.g. registry.k8s.io)
# - optional Private Services Access range + peering, only needed by Cloud SQL private IP

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  project                  = var.project_id
  name                     = "${var.name}-gke"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "router" {
  count = var.nat_enabled ? 1 : 0

  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  count = var.nat_enabled ? 1 : 0

  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Services Access: Cloud SQL gets a private IP inside this reserved range.
resource "google_compute_global_address" "psa" {
  count = var.psa_enabled ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  count = var.psa_enabled ? 1 : 0

  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa[0].name]
}
