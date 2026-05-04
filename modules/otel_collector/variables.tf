variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Cloud Run region."
  type        = string
  default     = "us-central1"
}

variable "image" {
  description = "Container image URI for ft-otel-collector. Updated on each GitHub Actions deploy."
  type        = string
  default     = "europe-west1-docker.pkg.dev/flowterra-dev/flowterra/ft-otel-collector:latest"
}

variable "labels" {
  description = "Labels to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "service_account_email" {
  description = "Service account email the Cloud Run service runs as (needs cloudtrace.agent + secretmanager.secretAccessor)."
  type        = string
}

variable "grafana_token_secret_id" {
  description = "Secret Manager secret ID for GRAFANA_TOKEN."
  type        = string
}

variable "grafana_endpoint_secret_id" {
  description = "Secret Manager secret ID for GRAFANA_OTLP_ENDPOINT."
  type        = string
}

variable "min_instances" {
  description = "Minimum Cloud Run instance count. Use 0 for dev/demo, 1 for prod."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum Cloud Run instance count."
  type        = number
  default     = 3
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated invocations. Set true for dev (easier testing); false for prod."
  type        = bool
  default     = false
}
