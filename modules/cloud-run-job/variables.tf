variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "job_name" {
  type = string
}

variable "container_name" {
  type        = string
  default     = "job"
  description = "Name of the single container in the job template."
}

variable "image" {
  type        = string
  description = "Initial container image. CI updates this outside Terraform — see lifecycle.ignore_changes."
}

variable "service_account_email" {
  type = string
}

variable "command" {
  type        = list(string)
  description = "Container entrypoint override (e.g. [\"npx\"])."
}

variable "args" {
  type        = list(string)
  description = "Args after command (e.g. [\"prisma\", \"migrate\", \"deploy\"])."
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "timeout" {
  type        = string
  default     = "600s"
  description = "Max execution time for a single job attempt."
}

variable "max_retries" {
  type        = number
  default     = 0
  description = "Retries on failure. Keep 0 for migrations to avoid double-apply races."
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
