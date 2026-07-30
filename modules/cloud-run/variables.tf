variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "service_name" {
  type = string
}

variable "image" {
  type        = string
  description = "Initial container image. Later deploys (CI/gcloud) manage this outside Terraform — see lifecycle.ignore_changes."
}

variable "service_account_email" {
  type = string
}

variable "port" {
  type    = number
  default = 3000
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 2
}

variable "allow_unauthenticated" {
  type    = bool
  default = false
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "secret_env_vars" {
  type = map(object({
    secret_id = string
    version   = optional(string, "latest")
  }))
  default     = {}
  description = "Env vars sourced from Secret Manager: { ENV_NAME = { secret_id = \"...\" } }"
}

variable "cloudsql_instance_connection_name" {
  type    = string
  default = null
}

variable "redis_sidecar_enabled" {
  type        = bool
  default     = false
  description = "Run redis:7-alpine as a sidecar container instead of provisioning Memorystore. Ephemeral, resets on scale-to-zero — fine for staging cache/sessions, not for prod."
}

variable "custom_domain" {
  type        = string
  default     = null
  description = "Optional hostname to map to this service (e.g. school-staging.m-romero.dev). Domain must already be verified in Google Search Console for this GCP project. DNS CNAME records are NOT created here — configure them at your DNS provider using output domain_dns_records."
}
