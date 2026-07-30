locals {
  # for_each can't key off a sensitive map — the keys (secret names) aren't
  # secret themselves, only the values are, so peel off just the names.
  secret_names = nonsensitive(toset(keys(var.secrets)))
}

resource "google_secret_manager_secret" "this" {
  for_each  = local.secret_names
  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each    = local.secret_names
  secret      = google_secret_manager_secret.this[each.value].id
  secret_data = var.secrets[each.value]
}
