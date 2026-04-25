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
