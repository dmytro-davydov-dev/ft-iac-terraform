output "secret_ids" {
  description = "Map of secret logical name → Secret Manager resource ID."
  value       = { for k, s in google_secret_manager_secret.secrets : k => s.id }
  sensitive   = true
}

output "secret_names" {
  description = "Map of secret logical name → secret_id (short name)."
  value       = { for k, s in google_secret_manager_secret.secrets : k => s.secret_id }
}
