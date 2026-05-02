output "service_url" {
  description = "The HTTPS URL of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.ft_api.uri
}

output "service_name" {
  description = "Cloud Run service name."
  value       = google_cloud_run_v2_service.ft_api.name
}
