output "connection_name" {
  value = google_sql_database_instance.this.connection_name
}

output "public_ip" {
  value = google_sql_database_instance.this.public_ip_address
}

output "database_name" {
  value = google_sql_database.this.name
}

output "database_user" {
  value = google_sql_user.this.name
}
