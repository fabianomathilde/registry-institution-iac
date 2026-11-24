# Docker repository for application images.
# Images are tagged with the git commit SHA; with immutable tags a SHA always means the same image.

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "repository_id" {
  type = string
}

variable "keep_count" {
  description = "Most recent image versions always kept, regardless of age."
  type        = number
  default     = 20
}

variable "immutable_tags" {
  description = "true: a tag (the git SHA) can never be moved to another image."
  type        = bool
  default     = true
}

variable "labels" {
  type    = map(string)
  default = {}
}

resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  format        = "DOCKER"
  description   = "Container images for ${var.repository_id}"
  labels        = var.labels

  docker_config {
    immutable_tags = var.immutable_tags
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-most-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_count
    }
  }

  cleanup_policies {
    id     = "delete-older-than-30-days"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "2592000s"
    }
  }
}

output "name" {
  value = google_artifact_registry_repository.this.name
}

output "location" {
  value = google_artifact_registry_repository.this.location
}

output "url" {
  description = "Registry path, e.g. us-central1-docker.pkg.dev/<project>/<repo>."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
