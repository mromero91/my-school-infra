output "email" {
  value = google_service_account.this.email
}

output "name" {
  description = "Full resource name (projects/{project}/serviceAccounts/{email}) — needed for service-account-level IAM bindings."
  value       = google_service_account.this.name
}
