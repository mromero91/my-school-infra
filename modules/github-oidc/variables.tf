variable "project_id" {
  type = string
}

variable "pool_id" {
  type    = string
  default = "github-actions-pool"
}

variable "provider_id" {
  type    = string
  default = "github-actions-provider"
}

variable "github_owner" {
  type        = string
  description = "GitHub org/user allowed to mint tokens against this pool. Anyone outside it is rejected at the provider level, before any per-repo IAM binding is even checked."
}
