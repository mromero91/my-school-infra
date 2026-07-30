data "google_project" "current" {
  project_id = var.project_id
}

locals {
  name_prefix = "school-${var.environment}"

  database_url = "postgresql://${module.database.database_user}:${var.db_password}@localhost/${module.database.database_name}?host=/cloudsql/${module.database.connection_name}&schema=public"

  # Prefer custom domain for CORS when set. Fallback avoids a circular module
  # dep (backend needs frontend origin before frontend module exists):
  # https://SERVICE-PROJECT_NUMBER.REGION.run.app
  run_app_frontend_url = "https://${local.name_prefix}-frontend-${data.google_project.current.number}.${var.region}.run.app"
  frontend_url = (
    var.frontend_domain != null && var.frontend_domain != ""
    ? "https://${var.frontend_domain}"
    : local.run_app_frontend_url
  )
  backend_public_url = (
    var.backend_domain != null && var.backend_domain != ""
    ? "https://${var.backend_domain}"
    : null # resolved after module.backend_service when no custom domain
  )
}

module "artifact_registry" {
  source        = "../../modules/artifact-registry"
  project_id    = var.project_id
  region        = var.region
  repository_id = local.name_prefix
  description   = "Docker images for the school app (${var.environment})"
}

module "uploads_bucket" {
  source      = "../../modules/storage"
  project_id  = var.project_id
  location    = var.region
  bucket_name = "${var.project_id}-${local.name_prefix}-uploads"
}

module "database" {
  source              = "../../modules/database"
  project_id          = var.project_id
  region              = var.region
  instance_name       = "${local.name_prefix}-db"
  database_name       = "school_db"
  database_user       = "school_app"
  database_password   = var.db_password
  authorized_networks = var.authorized_networks

  # Pilot has no real data yet — backups just add storage cost with
  # nothing worth restoring. Re-enable once there's real student data.
  backups_enabled = false
}

module "secrets" {
  source     = "../../modules/secrets"
  project_id = var.project_id
  secrets = {
    "${local.name_prefix}-database-url"       = local.database_url
    "${local.name_prefix}-jwt-secret"         = var.jwt_secret
    "${local.name_prefix}-jwt-refresh-secret" = var.jwt_refresh_secret
  }
}

module "backend_sa" {
  source       = "../../modules/iam"
  project_id   = var.project_id
  account_id   = "${local.name_prefix}-backend"
  display_name = "School backend (${var.environment})"
  roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/storage.objectAdmin",
  ]
}

module "frontend_sa" {
  source       = "../../modules/iam"
  project_id   = var.project_id
  account_id   = "${local.name_prefix}-frontend"
  display_name = "School frontend (${var.environment})"
  roles        = []
}

module "backend_service" {
  source                            = "../../modules/cloud-run"
  project_id                        = var.project_id
  region                            = var.region
  service_name                      = "${local.name_prefix}-backend"
  image                             = var.backend_image
  service_account_email             = module.backend_sa.email
  port                              = 3000
  min_instances                     = 0
  max_instances                     = 2
  allow_unauthenticated             = true
  cloudsql_instance_connection_name = module.database.connection_name
  custom_domain                     = var.backend_domain

  # Sidecar instead of Memorystore — see modules/cloud-run/main.tf. Fine for
  # a single pilot school's cache/session load, not durable across restarts.
  redis_sidecar_enabled = true

  env_vars = {
    NODE_ENV        = var.environment
    REDIS_HOST      = "localhost"
    REDIS_PORT      = "6379"
    GCP_BUCKET_NAME = module.uploads_bucket.bucket_name
    GCP_PROJECT_ID  = var.project_id
    FRONTEND_URL    = local.frontend_url
  }

  secret_env_vars = {
    DATABASE_URL       = { secret_id = module.secrets.secret_ids["${local.name_prefix}-database-url"] }
    JWT_SECRET         = { secret_id = module.secrets.secret_ids["${local.name_prefix}-jwt-secret"] }
    JWT_REFRESH_SECRET = { secret_id = module.secrets.secret_ids["${local.name_prefix}-jwt-refresh-secret"] }
  }
}

# One-shot Prisma migrate before each backend deploy (CI runs
# `gcloud run jobs execute --wait`). Same image/SA/Cloud SQL as the API;
# only DATABASE_URL is needed. Image tag is updated by CI (ignore_changes).
module "migrate_job" {
  source                            = "../../modules/cloud-run-job"
  project_id                        = var.project_id
  region                            = var.region
  job_name                          = "${local.name_prefix}-migrate"
  container_name                    = "migrate"
  image                             = var.backend_image
  service_account_email             = module.backend_sa.email
  cloudsql_instance_connection_name = module.database.connection_name
  command                           = ["npx"]
  args                              = ["prisma", "migrate", "deploy"]
  max_retries                       = 0

  env_vars = {
    NODE_ENV = var.environment
  }

  secret_env_vars = {
    DATABASE_URL = { secret_id = module.secrets.secret_ids["${local.name_prefix}-database-url"] }
  }
}

# Idempotent demo/bootstrap seed. NOT run by CI — execute manually after
# migrate when staging needs school/staff fixtures:
#   gcloud run jobs execute school-staging-seed --wait
module "seed_job" {
  source                            = "../../modules/cloud-run-job"
  project_id                        = var.project_id
  region                            = var.region
  job_name                          = "${local.name_prefix}-seed"
  container_name                    = "seed"
  image                             = var.backend_image
  service_account_email             = module.backend_sa.email
  cloudsql_instance_connection_name = module.database.connection_name
  command                           = ["node"]
  args                              = ["dist/prisma/seed.js"]
  max_retries                       = 0

  env_vars = {
    NODE_ENV               = "production"
    SEED_PRINT_CREDENTIALS = "false"
  }

  secret_env_vars = {
    DATABASE_URL = { secret_id = module.secrets.secret_ids["${local.name_prefix}-database-url"] }
  }
}

# NOTE: VITE_API_URL is baked in at *build* time by Vite, not read at
# container runtime — setting it as a Cloud Run env var here does nothing
# unless the frontend image's entrypoint does an envsubst/rebuild step.
# Pass output `vite_api_url` as the GitHub Actions variable VITE_API_URL
# (build arg in the frontend Docker build).
module "frontend_service" {
  source                = "../../modules/cloud-run"
  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-frontend"
  image                 = var.frontend_image
  service_account_email = module.frontend_sa.email
  port                  = 8080
  min_instances         = 0
  max_instances         = 2
  allow_unauthenticated = true
  custom_domain         = var.frontend_domain

  env_vars = {
    VITE_API_URL = "${coalesce(local.backend_public_url, module.backend_service.url)}/api/v1"
  }
}

# ─── CI/CD: GitHub Actions deploy access (Workload Identity Federation) ──────
# No JSON keys. Each repo's Actions workflow exchanges its OIDC token for a
# short-lived access token as its own dedicated "deployer" SA, scoped to only
# what deploying that one service requires.

module "github_oidc" {
  source       = "../../modules/github-oidc"
  project_id   = var.project_id
  github_owner = var.github_owner
}

module "backend_deployer_sa" {
  source       = "../../modules/iam"
  project_id   = var.project_id
  account_id   = "${local.name_prefix}-be-deployer"
  display_name = "CI deployer for backend (${var.environment})"
  roles = [
    "roles/run.developer",           # deploy/update the Cloud Run service, not project-wide run.admin
    "roles/artifactregistry.writer", # push images
  ]
}

module "frontend_deployer_sa" {
  source       = "../../modules/iam"
  project_id   = var.project_id
  account_id   = "${local.name_prefix}-fe-deployer"
  display_name = "CI deployer for frontend (${var.environment})"
  roles = [
    "roles/run.developer",
    "roles/artifactregistry.writer",
  ]
}

# Deploying a revision means telling Cloud Run "run as this runtime SA" —
# that requires serviceAccountUser on that *specific* SA, not project-wide.
resource "google_service_account_iam_member" "backend_deployer_actas_runtime" {
  service_account_id = module.backend_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.backend_deployer_sa.email}"
}

resource "google_service_account_iam_member" "frontend_deployer_actas_runtime" {
  service_account_id = module.frontend_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.frontend_deployer_sa.email}"
}

# Bind each deployer SA to *only* its own GitHub repo — my-school-api can never
# mint a token for the frontend deployer or vice versa.
resource "google_service_account_iam_member" "backend_deployer_wif" {
  service_account_id = module.backend_deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${module.github_oidc.pool_name}/attribute.repository/${var.github_owner}/my-school-api"
}

resource "google_service_account_iam_member" "frontend_deployer_wif" {
  service_account_id = module.frontend_deployer_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${module.github_oidc.pool_name}/attribute.repository/${var.github_owner}/my-school-app"
}
