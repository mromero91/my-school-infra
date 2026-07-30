resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      name  = "app"
      image = var.image

      ports {
        container_port = var.port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env_vars
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = coalesce(env.value.version, "latest")
            }
          }
        }
      }

      dynamic "volume_mounts" {
        for_each = var.cloudsql_instance_connection_name != null ? [1] : []
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }
    }

    # Redis sidecar for staging cache/sessions — avoids paying for Memorystore.
    # Reachable at localhost:6379 from the app container; state resets on
    # scale-to-zero, which is fine for a pilot but not for anything that
    # needs durable cache/session data.
    dynamic "containers" {
      for_each = var.redis_sidecar_enabled ? [1] : []
      content {
        name  = "redis"
        image = "redis:7-alpine"

        resources {
          limits = {
            cpu    = "1"
            memory = "256Mi"
          }
        }
      }
    }

    dynamic "volumes" {
      for_each = var.cloudsql_instance_connection_name != null ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloudsql_instance_connection_name]
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      # Deploys (CI/CD, `gcloud run deploy`) push new image tags outside
      # Terraform — don't fight them on every plan.
      template[0].containers[0].image,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Preview Cloud Run domain mapping — fine for staging; prefer a global HTTPS
# load balancer for production. Requires the domain (or parent) verified in
# Search Console against this GCP project.
resource "google_cloud_run_domain_mapping" "custom" {
  count    = var.custom_domain != null && var.custom_domain != "" ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = var.custom_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.this.name
  }
}
