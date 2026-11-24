# Foundation: what everything else runs on. Changes rarely.
#   project.yaml    -> APIs, GitHub Workload Identity Federation (pool + provider)
#   network.yaml    -> VPC, optional NAT, static ingress IPs, optional DNS zone
#   kubernetes.yaml -> GKE Autopilot cluster
#   databases.yaml  -> only whether Cloud SQL exists (it needs the Private Services Access peering)

module "apis" {
  source     = "../../modules/project-apis"
  project_id = local.project
  services = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "firestore.googleapis.com",
    "iamcredentials.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "spanner.googleapis.com",
    "sqladmin.googleapis.com",
    "sts.googleapis.com",
  ]
}

module "github_wif" {
  source       = "../../modules/github-wif"
  project_id   = local.project
  github_owner = local.s.project.github_owner

  depends_on = [module.apis]
}

module "network" {
  source        = "../../modules/network"
  project_id    = local.project
  region        = local.region
  name          = "registry-institution"
  subnet_cidr   = local.s.network.subnet_cidr
  pods_cidr     = local.s.network.pods_cidr
  services_cidr = local.s.network.services_cidr
  nat_enabled   = local.s.network.nat_enabled
  psa_enabled   = length(local.s.cloudsql) > 0

  depends_on = [module.apis]
}

module "gke" {
  count  = local.s.cluster.enabled ? 1 : 0
  source = "../../modules/gke-autopilot"

  project_id          = local.project
  region              = local.region
  name                = local.s.cluster.name
  network_self_link   = module.network.network_self_link
  subnet_self_link    = module.network.subnet_self_link
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  release_channel     = local.s.cluster.release_channel
  deletion_protection = local.s.project.deletion_protection
  labels              = local.s.labels
}

# Global static IPs for the GKE Ingress of each app (network.yaml: ingress.ips).
# Each one is a billed resource (~USD 7/month while reserved and unused by a load balancer).
resource "google_compute_global_address" "ingress" {
  for_each = { for app, name in local.s.ingress_ips : app => name if local.s.network.ingress_enabled }

  name   = each.value
  labels = local.s.labels

  depends_on = [module.apis]
}

module "dns_zone" {
  count  = local.s.network.domain != "" ? 1 : 0
  source = "../../modules/dns-zone"

  project_id = local.project
  zone_name  = "registry-institution"
  domain     = local.s.network.domain
  labels     = local.s.labels

  depends_on = [module.apis]
}
