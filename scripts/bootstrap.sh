#!/usr/bin/env bash
# One-time setup before the first `terraform init`:
#   - enables the GCP APIs this project's resources need
#   - creates the GCS bucket that holds Terraform state
#
# Usage: ./scripts/bootstrap.sh <project_id> [region]
set -euo pipefail

PROJECT_ID="${1:?Usage: ./scripts/bootstrap.sh <project_id> [region]}"
REGION="${2:-us-central1}"
STATE_BUCKET="${PROJECT_ID}-tfstate"

echo "Enabling required APIs on ${PROJECT_ID}..."
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project "${PROJECT_ID}"

if gsutil ls -b "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "State bucket gs://${STATE_BUCKET} already exists."
else
  echo "Creating state bucket gs://${STATE_BUCKET}..."
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
fi

echo
echo "Done. Now run, from environments/staging/:"
echo "  terraform init -backend-config=\"bucket=${STATE_BUCKET}\" -backend-config=\"prefix=staging\""
