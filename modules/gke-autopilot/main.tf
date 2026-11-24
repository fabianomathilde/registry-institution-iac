# Regional GKE Autopilot cluster with private nodes.
# - Workload Identity Federation for GKE is always on in Autopilot (pool: <project>.svc.id.goog)
# - Secret Manager add-on lets pods mount Secret Manager secrets as files (SecretProviderClass)
# - The control plane keeps a public endpoint so GitHub-hosted runners can deploy; restrict it
#   with master_authorized_networks once you deploy from fixed IPs (self-hosted runner, bastion).

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  enable_autopilot    = true
  deletion_protection = var.deletion_protection

  network    = var.network_self_link
  subnetwork = var.subnet_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  secret_manager_config {
    enabled = true
  }

  # Weekend maintenance window (UTC), so upgrades don't land in the middle of a work session.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T05:00:00Z"
      end_time   = "2026-01-03T11:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = var.labels
}
