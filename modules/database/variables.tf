variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "database_version" {
  type    = string
  default = "POSTGRES_16"
}

variable "tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Smallest shared-core tier — fine for a single-school pilot, not for real concurrent load."
}

variable "disk_size_gb" {
  type    = number
  default = 10
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "backups_enabled" {
  type    = bool
  default = true
}

variable "database_name" {
  type = string
}

variable "database_user" {
  type = string
}

variable "database_password" {
  type      = string
  sensitive = true
}

variable "authorized_networks" {
  type = list(object({
    name = string
    cidr = string
  }))
  default     = []
  description = "IPs allowed to connect directly (e.g. your machine for prisma migrate). Cloud Run doesn't need this — it connects via the Cloud SQL connector regardless."
}
