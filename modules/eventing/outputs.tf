output "topic_name" {
  value = google_pubsub_topic.this.name
}

output "topic_id" {
  value = google_pubsub_topic.this.id
}

output "table" {
  value = var.bigquery ? "${var.project_id}.${var.dataset_id}.${var.table_id}" : null
}
