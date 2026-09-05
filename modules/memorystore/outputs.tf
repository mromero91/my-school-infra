output "instance_id" {
  description = "Redis instance ID (name)"
  value       = google_redis_instance.this.id
}

output "host" {
  description = "Redis instance host/IP (connection point)"
  value       = google_redis_instance.this.host
}

output "port" {
  description = "Redis instance port (typically 6379)"
  value       = google_redis_instance.this.port
}

output "redis_url" {
  description = "Redis connection URL (redis://host:port)"
  value       = "redis://${google_redis_instance.this.host}:${google_redis_instance.this.port}"
}

output "auth_string" {
  description = "Redis AUTH command suffix (password if auth_enabled, empty otherwise)"
  value       = var.auth_enabled ? "--pass ${google_redis_instance.this.auth_string}" : ""
  sensitive   = true
}

output "current_location_id" {
  description = "Zone of the current Redis instance"
  value       = google_redis_instance.this.current_location_id
}
