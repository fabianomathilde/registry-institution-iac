# One Firestore (Native mode) database plus its composite indexes.
#
# "(default)" is the only database covered by the Firestore free tier (1 GiB, 50k reads,
# 20k writes, 20k deletes per day). Any other database_id is a named database, billed from
# the first operation. Named databases are also the way to isolate apps: IAM conditions can
# scope a role to one database, not to a collection.

variable "project_id" {
  type = string
}

variable "database_id" {
  description = "\"(default)\" or a name for a named (paid) database."
  type        = string
}

variable "location" {
  description = "Region (e.g. us-central1) or multi-region (nam5). Cannot be changed later."
  type        = string
}

variable "indexes" {
  description = "Composite indexes: collection + fields, all ascending."
  type = list(object({
    collection = string
    fields     = list(string)
  }))
  default = []
}

variable "deletion_protection" {
  type    = bool
  default = true
}

resource "google_firestore_database" "this" {
  project     = var.project_id
  name        = var.database_id
  location_id = var.location
  type        = "FIRESTORE_NATIVE"

  delete_protection_state = var.deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  # ABANDON: "terraform destroy" only forgets the database. The free (default) database can't
  # really be recreated quickly, and data should never be lost by a Terraform run.
  deletion_policy = "ABANDON"
}

resource "google_firestore_index" "this" {
  for_each = { for idx in var.indexes : "${idx.collection}:${join(",", idx.fields)}" => idx }

  project     = var.project_id
  database    = google_firestore_database.this.name
  collection  = each.value.collection
  query_scope = "COLLECTION"

  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path = fields.value
      order      = "ASCENDING"
    }
  }
}

output "name" {
  value = google_firestore_database.this.name
}

output "location" {
  value = google_firestore_database.this.location_id
}
