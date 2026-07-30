output "url" {
  value = google_cloud_run_v2_service.this.uri
}

output "name" {
  value = google_cloud_run_v2_service.this.name
}

output "custom_domain" {
  description = "Mapped custom hostname, or null when unused."
  value       = var.custom_domain != null && var.custom_domain != "" ? var.custom_domain : null
}

output "custom_url" {
  description = "https://custom-domain when mapped, otherwise the default *.run.app URL."
  value = (
    var.custom_domain != null && var.custom_domain != ""
    ? "https://${var.custom_domain}"
    : google_cloud_run_v2_service.this.uri
  )
}

output "domain_dns_records" {
  description = "DNS records to create at your DNS provider for the custom domain mapping."
  value = try(
    [
      for r in google_cloud_run_domain_mapping.custom[0].status[0].resource_records : {
        type   = r.type
        name   = r.name
        rrdata = r.rrdata
      }
    ],
    []
  )
}
