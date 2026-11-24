# One Cloud SQL for PostgreSQL instance, private IP only (an entry under cloudsql: in databases.yaml).
# Databases, users and password secrets on it are created by stacks/components. Apps reach it
# through the Cloud SQL Auth Proxy (TLS + IAM authorization: roles/cloudsql.client).

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = var.availability_type
    activation_policy = var.activation_policy
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true
    user_labels       = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "06:00"
      point_in_time_recovery_enabled = var.point_in_time_recovery

      backup_retention_settings {
        retained_backups = var.retained_backups
      }
    }

    insights_config {
      query_insights_enabled = true
    }
  }

  # Start/stop is an operational action (scripts/env.sh), not a configuration change:
  # Terraform sets the initial state and then leaves it alone.
  lifecycle {
    ignore_changes = [settings[0].activation_policy]
  }
}
