output "job_name" {
  description = "Name of the PotreeConverter Cloud Run Job."
  value       = google_cloud_run_v2_job.potree_converter.name
}

output "service_account_email" {
  description = "Email of the PotreeConverter job service account."
  value       = google_service_account.potree_job.email
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository ID for drone pipeline images."
  value       = google_artifact_registry_repository.drone.repository_id
}
