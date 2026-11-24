variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "subnet_self_link" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "release_channel" {
  description = "RAPID, REGULAR or STABLE."
  type        = string
  default     = "REGULAR"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the control plane. Empty = any (authenticated) client."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}
