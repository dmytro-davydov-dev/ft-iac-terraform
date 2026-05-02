output "service_account_email" {
  description = "Email of the EMQX VM service account."
  value       = google_service_account.emqx.email
}

output "mig_id" {
  description = "Resource ID of the EMQX Managed Instance Group."
  value       = google_compute_region_instance_group_manager.emqx.id
}

output "instance_template_id" {
  description = "Resource ID of the current EMQX instance template."
  value       = google_compute_instance_template.emqx.id
}
