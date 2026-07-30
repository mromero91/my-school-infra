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
  default = "staging"
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
