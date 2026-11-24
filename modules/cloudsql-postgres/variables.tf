variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  description = "Instance name. Cloud SQL reserves a deleted name for about a week."
  type        = string
}

variable "network_id" {
  description = "VPC id with a Private Services Access connection."
  type        = string
}

variable "database_version" {
  type    = string
  default = "POSTGRES_17"
}

variable "tier" {
  description = "Machine tier. db-f1-micro (shared core) is the cheapest; not covered by the SLA."
  type        = string
  default     = "db-f1-micro"
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (HA, roughly double the cost)."
  type        = string
  default     = "ZONAL"
}

variable "activation_policy" {
  description = "Initial state only: ALWAYS = running, NEVER = stopped (storage-only cost). Afterwards start/stop with scripts/env.sh."
  type        = string
  default     = "ALWAYS"
}

variable "point_in_time_recovery" {
  type    = bool
  default = false
}

variable "retained_backups" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
