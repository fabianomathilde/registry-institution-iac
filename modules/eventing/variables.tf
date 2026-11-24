variable "project_id" {
  type = string
}

variable "topic_name" {
  type = string
}

variable "bigquery" {
  description = "Stream the topic into a BigQuery table."
  type        = bool
  default     = false
}

variable "dataset_id" {
  description = "Existing BigQuery dataset (required when bigquery = true)."
  type        = string
  default     = null
}

variable "table_id" {
  type    = string
  default = null
}

variable "allow_destroy_data" {
  description = "true in dev: terraform destroy also deletes the table data."
  type        = bool
  default     = false
}

variable "labels" {
  type    = map(string)
  default = {}
}
