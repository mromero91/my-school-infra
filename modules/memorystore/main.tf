resource "google_redis_instance" "this" {
  project             = var.project_id
  name                = var.instance_id
  region              = var.region
  tier                = var.tier
  memory_size_gb      = var.memory_size_gb
  redis_version       = var.redis_version
  display_name        = var.display_name
  auth_enabled        = var.auth_enabled
  transit_encryption_mode = var.transit_encryption_mode

  # High Availability: ensure we provision HA within the same region.
  # STANDARD_HA requires connect_mode = "DIRECT_PEERING" (default) and
  # provides automatic failover within the region using replica standby instances.
  connect_mode = "DIRECT_PEERING"

  # Access is controlled via VPC peering and IAM roles, not via
  # authorized_networks (which would be for private service access).
  # Cloud Run instances in the same region connect via private IP.
  lifecycle {
    prevent_destroy = true
  }

  labels = var.labels
}
