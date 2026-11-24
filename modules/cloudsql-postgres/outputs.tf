output "instance_name" {
  value = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "<project>:<region>:<instance>, used by the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip" {
  value = google_sql_database_instance.this.private_ip_address
}
