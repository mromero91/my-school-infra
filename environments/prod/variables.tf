variable "project_id" {
  type        = string
  description = "GCP project ID to deploy into."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "jwt_refresh_secret" {
  type      = string
  sensitive = true
}

variable "backend_image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello:latest"
  description = "Placeholder until the first real image is pushed to Artifact Registry and deployed via CI/`gcloud run deploy`."
}

variable "frontend_image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello:latest"
}

variable "authorized_networks" {
  type = list(object({
    name = string
    cidr = string
  }))
  default     = []
  description = "IPs allowed to connect directly to Cloud SQL (e.g. your machine for `prisma migrate deploy`). Cloud Run doesn't need this."
}

variable "github_owner" {
  type        = string
  default     = "mromero91"
  description = "GitHub org/user that owns the backend and frontend repos — used to scope the Workload Identity Federation provider."
}

variable "frontend_domain" {
  type        = string
  default     = null
  description = "Custom hostname for the SPA (e.g. school-staging.m-romero.dev). Leave null to use only the *.run.app URL."
}

variable "backend_domain" {
  type        = string
  default     = null
  description = "Custom hostname for the API (e.g. school-staging-api.m-romero.dev). Leave null to use only the *.run.app URL."
}

# ─── Production HA Configuration ────────────────────────────────────────

variable "db_instance_class" {
  type        = string
  default     = "db-custom-2-8192"
  description = "Cloud SQL machine type for production HA (e.g. db-custom-2-8192: 2 vCPU, 8 GB RAM)"
}

variable "redis_tier" {
  type        = string
  default     = "STANDARD_HA"
  description = "Redis tier: BASIC (no HA, resets on maintenance) or STANDARD_HA (active-passive with failover)"
}

variable "redis_memory_size_gb" {
  type        = number
  default     = 1
  description = "Memorystore Redis memory size in GB (1-300 for STANDARD_HA)"
}

variable "redis_auth_enabled" {
  type        = bool
  default     = true
  description = "Enable AUTH for Memorystore Redis (recommended for prod)"
}
