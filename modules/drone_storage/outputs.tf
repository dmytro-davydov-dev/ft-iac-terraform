output "bucket_name" {
  description = "Name of the drone storage GCS bucket."
  value       = google_storage_bucket.drone.name
}

output "bucket_url" {
  description = "GCS URL (gs://) of the drone storage bucket."
  value       = google_storage_bucket.drone.url
}
