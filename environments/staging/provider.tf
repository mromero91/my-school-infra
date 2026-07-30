terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    # Configure at `terraform init` time, don't hardcode a bucket here:
    #   terraform init -backend-config="bucket=<state-bucket>" -backend-config="prefix=staging"
    # `scripts/bootstrap.sh` creates the state bucket.
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
