variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Run Job and Artifact Registry."
  type        = string
  default     = "europe-west1"
}

variable "image" {
  description = "Docker image for the PotreeConverter job. CI updates this after each build."
  type        = string
}

variable "drone_bucket_name" {
  description = "Name of the GCS drone storage bucket (from module.drone_storage)."
  type        = string
}

variable "ft_api_sa_email" {
  description = "ft-api service account email — granted run.invoker so ft-api can trigger this job."
  type        = string
}

variable "supabase_url_secret_id" {
  description = "Secret Manager secret ID for the Supabase project URL."
  type        = string
  default     = "flowterra-supabase-url"
}

variable "supabase_service_key_secret_id" {
  description = "Secret Manager secret ID for the Supabase service role key."
  type        = string
  default     = "flowterra-supabase-service-key"
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
