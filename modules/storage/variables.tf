variable "project_id" {
  type = string
}

variable "location" {
  type    = string
  default = "US"
}

variable "bucket_name" {
  type = string
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Allow bucket deletion even if it has objects. Fine for staging, dangerous for prod."
}

variable "cors_origins" {
  type    = list(string)
  default = ["*"]
}

variable "retention_days" {
  type        = number
  default     = 365
  description = "Delete objects older than this. Set high or override per-environment."
}
