# Spanner 90-day free trial instance (10 GB, no backups, no SLA). One per project lifecycle.
# After 90 days it stops serving and is deleted 30 days later unless upgraded to a paid instance;
# Terraform never upgrades it. Off by default: enable it when you start the Spanner adapter, so
# the 90-day clock doesn't run while you're not using it.
#
# The optin schema uses a Postgres sequence and a partial unique index, so it is not a drop-in
# for Spanner: the Spanner adapter is a new driven adapter with its own schema (ADR needed).

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  type    = string
  default = "optin-trial"
}

variable "labels" {
  type    = map(string)
  default = {}
}

resource "google_spanner_instance" "trial" {
  project       = var.project_id
  name          = var.name
  display_name  = "Optin free trial"
  config        = "regional-${var.region}"
  instance_type = "FREE_INSTANCE"
  force_destroy = true
  labels        = var.labels
}

resource "google_spanner_database" "optin" {
  project             = var.project_id
  instance            = google_spanner_instance.trial.name
  name                = "optin"
  database_dialect    = "POSTGRESQL"
  deletion_protection = false
}

output "instance" {
  value = google_spanner_instance.trial.name
}

output "database" {
  value = google_spanner_database.optin.name
}
