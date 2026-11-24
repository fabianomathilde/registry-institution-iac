output "firestore" {
  description = "Key in databases.yaml -> database id and location."
  value       = { for k, m in module.firestore : k => { database_id = m.name, location = m.location } }
}

output "cloudsql" {
  description = "Instance -> connection name (for the Cloud SQL Auth Proxy), private IP and databases with their password secret."
  value = {
    for k, m in module.cloudsql : k => {
      connection_name = m.connection_name
      private_ip      = m.private_ip
      databases = {
        for key, d in local.sql_databases : d.database => { user = d.database, password_secret = d.secret } if d.instance == k
      }
    }
  }
}

output "spanner" {
  value = local.s.spanner_trial ? { instance = module.spanner_trial[0].instance, database = module.spanner_trial[0].database } : null
}

output "topics" {
  description = "Topic -> id and BigQuery table (null when not streamed)."
  value       = { for k, m in module.topics : k => { id = m.topic_id, table = m.table } }
}

output "secrets" {
  description = "Secret name -> id (secrets.yaml plus the generated Cloud SQL passwords)."
  value = merge(
    { for k, s in google_secret_manager_secret.this : k => s.id },
    { for k, s in google_secret_manager_secret.sql : s.secret_id => s.id },
  )
}

output "registries" {
  description = "Registry -> location, name and image path prefix."
  value       = { for k, m in module.registry : k => { location = m.location, name = m.name, url = m.url } }
}
