# One Pub/Sub topic, optionally streamed into a BigQuery table through a BigQuery subscription
# (no consumer code). The dataset is created by the caller (stacks/components), together with
# the Pub/Sub service agent's permission to write into it.

resource "google_pubsub_topic" "this" {
  project                    = var.project_id
  name                       = var.topic_name
  message_retention_duration = "604800s" # 7 days: lets you replay into a new subscription
  labels                     = var.labels
}

# Schema expected by a BigQuery subscription with write_metadata = true.
resource "google_bigquery_table" "this" {
  count = var.bigquery ? 1 : 0

  project             = var.project_id
  dataset_id          = var.dataset_id
  table_id            = var.table_id
  deletion_protection = !var.allow_destroy_data
  labels              = var.labels

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }

  schema = jsonencode([
    { name = "subscription_name", type = "STRING", mode = "NULLABLE" },
    { name = "message_id", type = "STRING", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "data", type = "STRING", mode = "NULLABLE", description = "Event payload (JSON text)" },
    { name = "attributes", type = "STRING", mode = "NULLABLE", description = "Message attributes (JSON text)" },
  ])
}

resource "google_pubsub_subscription" "to_bigquery" {
  count = var.bigquery ? 1 : 0

  project = var.project_id
  name    = "${var.topic_name}-to-bigquery"
  topic   = google_pubsub_topic.this.id
  labels  = var.labels

  bigquery_config {
    table          = "${var.project_id}.${var.dataset_id}.${google_bigquery_table.this[0].table_id}"
    write_metadata = true
  }
}
