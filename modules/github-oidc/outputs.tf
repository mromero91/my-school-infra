output "pool_name" {
  description = "Full resource name of the pool, e.g. projects/123/locations/global/workloadIdentityPools/github-actions-pool"
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Full resource name to put in the GitHub Actions `workload_identity_provider` input"
  value       = google_iam_workload_identity_pool_provider.github.name
}
