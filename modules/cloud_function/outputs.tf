output "function_name" {
  description = "Name of the deployed Cloud Function."
  value       = google_cloudfunctions2_function.ingest_fn.name
}

output "function_uri" {
  description = "HTTPS URI of the Cloud Function service (Cloud Run backing)."
  value       = google_cloudfunctions2_function.ingest_fn.service_config[0].uri
}

output "service_account_email" {
  description = "Email of the ingest-fn service account."
  value       = google_service_account.ingest_fn.email
}

output "source_bucket" {
  description = "GCS bucket storing function source zips."
  value       = google_storage_bucket.fn_source.name
}
