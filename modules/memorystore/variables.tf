variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for Memorystore instance"
}

variable "instance_id" {
  type        = string
  description = "Redis instance ID (name)"
}

variable "tier" {
  type        = string
  default     = "STANDARD_HA"
  description = "Redis tier: BASIC (no HA, resets on maintenance), STANDARD_HA (active-passive HA with auto-failover)"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "Tier must be BASIC or STANDARD_HA."
  }
}

variable "memory_size_gb" {
  type        = number
  description = "Memory size in GB (1-300 for STANDARD_HA)"
  validation {
    condition     = var.memory_size_gb >= 1 && var.memory_size_gb <= 300
    error_message = "Memory size must be between 1 and 300 GB."
  }
}

variable "redis_version" {
  type        = string
  default     = "redis_7_x"
  description = "Redis version (e.g., redis_7_x)"
}

variable "display_name" {
  type        = string
  default     = ""
  description = "Human-readable display name"
}

variable "auth_enabled" {
  type        = bool
  default     = true
  description = "Enable AUTH for the Redis instance (requires password)"
}

variable "transit_encryption_mode" {
  type        = string
  default     = "SERVER_AUTHENTICATION"
  description = "Transit encryption mode: SERVER_AUTHENTICATION (recommended for prod)"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "GCP resource labels"
}
