output "project_id" {
  value = local.project
}

output "project_number" {
  value = data.google_project.this.number
}

output "region" {
  value = local.region
}

output "environment" {
  value = local.s.project.environment
}

output "network_id" {
  value = module.network.network_id
}

output "psa_connection_id" {
  value = module.network.psa_connection_id
}

output "cluster" {
  description = "null when kubernetes.yaml has cluster.enabled: false."
  value = local.s.cluster.enabled ? {
    name           = module.gke[0].name
    location       = module.gke[0].location
    endpoint       = module.gke[0].endpoint
    ca_certificate = module.gke[0].ca_certificate
  } : null
  sensitive = true
}

output "cluster_name" {
  value = local.s.cluster.enabled ? module.gke[0].name : null
}

output "wif_pool_name" {
  value = module.github_wif.pool_name
}

output "wif_provider_name" {
  value = module.github_wif.provider_name
}

output "ingress_ips" {
  description = "App name -> static IP name and address."
  value       = { for app, addr in google_compute_global_address.ingress : app => { name = addr.name, address = addr.address } }
}

output "dns_zone" {
  value = local.s.network.domain != "" ? {
    name         = module.dns_zone[0].name
    domain       = local.s.network.domain
    name_servers = module.dns_zone[0].name_servers
  } : null
}

data "google_project" "this" {
  project_id = local.project
}
