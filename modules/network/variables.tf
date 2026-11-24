variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  description = "VPC name; also the prefix for subnet, router, NAT and PSA range."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary range of the GKE subnet (nodes)."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary range for pods. Autopilot recommends /17 or larger."
  type        = string
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes services."
  type        = string
}

variable "psa_prefix_length" {
  description = "Size of the Private Services Access range used by Cloud SQL."
  type        = number
  default     = 20
}

variable "nat_enabled" {
  description = "Cloud NAT for outbound internet from private nodes (needed for public images such as ExternalDNS)."
  type        = bool
  default     = false
}

variable "psa_enabled" {
  description = "Private Services Access peering (needed only for Cloud SQL private IP)."
  type        = bool
  default     = false
}
