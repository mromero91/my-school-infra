# Lets GitHub Actions authenticate to GCP with short-lived OIDC tokens instead
# of a long-lived service account JSON key. One pool/provider per project is
# enough — individual repos are scoped later via per-SA IAM bindings on
# `attribute.repository`, not here.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens for CI/CD deploys"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"              = "assertion.sub"
    "attribute.repository"        = "assertion.repository"
    "attribute.repository_owner"  = "assertion.repository_owner"
    "attribute.ref"               = "assertion.ref"
  }

  # Belt-and-suspenders: reject tokens from outside this GitHub org/user even
  # before checking which repo they came from.
  attribute_condition = "assertion.repository_owner == \"${var.github_owner}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
