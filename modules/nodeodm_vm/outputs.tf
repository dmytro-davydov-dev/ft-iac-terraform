output "service_account_email" {
  description = "Email of the NodeODM VM service account."
  value       = google_service_account.nodeodm.email
}

output "instance_name" {
  description = "Name of the NodeODM Spot VM instance."
  value       = google_compute_instance.nodeodm.name
}

output "instance_self_link" {
  description = "Self-link of the NodeODM Spot VM instance."
  value       = google_compute_instance.nodeodm.self_link
}
