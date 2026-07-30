variable "project_id" {
  type = string
}

variable "secrets" {
  type        = map(string)
  description = "Map of secret_id => secret value (plaintext, provided by caller). Values are sensitive."
  sensitive   = true
}
