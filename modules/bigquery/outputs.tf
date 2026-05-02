output "dataset_id" {
  description = "BigQuery dataset ID."
  value       = google_bigquery_dataset.flowterra.dataset_id
}

output "dataset_self_link" {
  description = "Self-link of the BigQuery dataset."
  value       = google_bigquery_dataset.flowterra.self_link
}

output "location_events_table_id" {
  description = "Full table ID for location_events (project.dataset.table)."
  value       = "${var.project_id}.${google_bigquery_dataset.flowterra.dataset_id}.${google_bigquery_table.location_events.table_id}"
}

output "geofence_events_table_id" {
  description = "Full table ID for geofence_events (project.dataset.table)."
  value       = "${var.project_id}.${google_bigquery_dataset.flowterra.dataset_id}.${google_bigquery_table.geofence_events.table_id}"
}
