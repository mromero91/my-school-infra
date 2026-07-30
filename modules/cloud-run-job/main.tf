resource "google_cloud_run_v2_job" "this" {
  project  = var.project_id
  name     = var.job_name
  location = var.region

  template {
    template {
      service_account = var.service_account_email
      timeout         = var.timeout
      max_retries     = var.max_retries

      containers {
        name    = "migrate"
        image   = var.image
        command = var.command
        args    = var.args

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
  }

  lifecycle {
    ignore_changes = [
      # CI updates the image tag on each deploy — don't fight them on plan.
      template[0].template[0].containers[0].image,
    ]
  }
}
