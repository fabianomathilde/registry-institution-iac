# Enables the Google APIs a project needs. APIs are never disabled on destroy:
# disabling an API can break resources that other stacks (or people) still use.

variable "project_id" {
  description = "Project where the APIs are enabled."
  type        = string
}

variable "services" {
  description = "API service names, e.g. container.googleapis.com."
  type        = list(string)
}

resource "google_project_service" "this" {
  for_each = toset(var.services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

output "services" {
  description = "Enabled API service names."
  value       = [for s in google_project_service.this : s.service]
}
