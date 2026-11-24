# Public Cloud DNS zone managed by ExternalDNS.
# After the first apply, point your registrar (or the parent zone) at the name_servers output.

variable "project_id" {
  type = string
}

variable "zone_name" {
  description = "Cloud DNS resource name, e.g. registry-institution-dev."
  type        = string
}

variable "domain" {
  description = "DNS name without the trailing dot, e.g. dev.registry-institution.com.br."
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

resource "google_dns_managed_zone" "this" {
  project     = var.project_id
  name        = var.zone_name
  dns_name    = "${var.domain}."
  description = "Public zone for ${var.domain}, records managed by ExternalDNS"
  visibility  = "public"
  labels      = var.labels

  dnssec_config {
    state = "on"
  }
}

output "name" {
  value = google_dns_managed_zone.this.name
}

output "name_servers" {
  value = google_dns_managed_zone.this.name_servers
}
