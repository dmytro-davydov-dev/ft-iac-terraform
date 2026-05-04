output "project_id" {
  description = "Active GCP project for this workspace."
  value       = local.project_id
}

output "workspace" {
  description = "Active Terraform workspace."
  value       = terraform.workspace
}

output "firestore_database_name" {
  description = "Firestore database name."
  value       = module.firestore.database_name
}

output "pubsub_topic_ids" {
  description = "Map of logical name → full Pub/Sub topic ID."
  value       = module.pubsub.topic_ids
}

output "secret_ids" {
  description = "Map of secret name → Secret Manager resource ID."
  value       = module.secrets.secret_ids
  sensitive   = true
}

# OBS Phase 1 outputs
output "otel_collector_url" {
  description = "HTTPS URL of the ft-otel-collector Cloud Run service."
  value       = module.otel_collector.service_url
}

output "otel_collector_grpc_endpoint" {
  description = "gRPC OTLP endpoint for instrumented services (host only; Cloud Run adds TLS on port 443)."
  value       = module.otel_collector.grpc_otlp_endpoint
}

# Phase 4 outputs
output "bq_dataset_id" {
  description = "BigQuery dataset ID for this workspace."
  value       = module.bigquery.dataset_id
}

output "bq_location_events_table" {
  description = "Full BigQuery table ID for location_events."
  value       = module.bigquery.location_events_table_id
}

output "bq_geofence_events_table" {
  description = "Full BigQuery table ID for geofence_events."
  value       = module.bigquery.geofence_events_table_id
}

output "ingest_fn_name" {
  description = "Deployed Cloud Function name."
  value       = module.cloud_function.function_name
}

output "emqx_mig_id" {
  description = "EMQX Managed Instance Group resource ID."
  value       = module.emqx_vm.mig_id
}
