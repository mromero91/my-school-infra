output "migrate_job_name" {
  description = "Cloud Run Job name for `gcloud run jobs execute` (prisma migrate deploy)."
  value       = module.migrate_job.name
}

output "seed_job_name" {
  description = "Cloud Run Job name for manual bootstrap seed (`node dist/prisma/seed.js`)."
  value       = module.seed_job.name
}

output "backend_url" {
  description = "Public API base URL (custom domain when set, else *.run.app)."
  value       = module.backend_service.custom_url
}

output "frontend_url" {
  description = "Public SPA URL (custom domain when set, else *.run.app)."
  value       = module.frontend_service.custom_url
}

output "vite_api_url" {
  description = "Value for the GitHub Actions variable VITE_API_URL on my-school-app (build-time)."
  value       = "${module.backend_service.custom_url}/api/v1"
}

output "domain_dns_records" {
  description = "DNS records to create at your DNS provider for Cloud Run domain mappings."
  value = {
    frontend = module.frontend_service.domain_dns_records
    backend  = module.backend_service.domain_dns_records
  }
}

output "database_connection_name" {
  value = module.database.connection_name
}

output "database_public_ip" {
  value = module.database.public_ip
}

output "artifact_registry_repository" {
  value = module.artifact_registry.repository_url
}

output "uploads_bucket" {
  value = module.uploads_bucket.bucket_name
}

output "workload_identity_provider" {
  description = "Value for the `workload_identity_provider` input in google-github-actions/auth"
  value       = module.github_oidc.provider_name
}

output "backend_deployer_email" {
  description = "Value for the `service_account` input in my-school-api's deploy workflow"
  value       = module.backend_deployer_sa.email
}

output "frontend_deployer_email" {
  description = "Value for the `service_account` input in my-school-app's deploy workflow"
  value       = module.frontend_deployer_sa.email
}
