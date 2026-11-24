output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_self_link" {
  value = google_compute_subnetwork.gke.self_link
}

output "pods_range_name" {
  value = "pods"
}

output "services_range_name" {
  value = "services"
}

output "psa_connection_id" {
  description = "Use as a dependency for anything that needs a private IP from PSA (Cloud SQL)."
  value       = try(google_service_networking_connection.psa[0].id, null)
}
