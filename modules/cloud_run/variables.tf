variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Cloud Run region."
  type        = string
  default     = "europe-west1"
}

variable "image" {
  description = "Container image URI. Updated on each GitHub Actions deploy."
  type        = string
  default     = "europe-west1-docker.pkg.dev/flowterra-dev/flowterra/ft-api:latest"
}

variable "labels" {
  description = "Labels to apply to the Cloud Run service."
  type        = map(string)
  default     = {}
}

variable "allowed_origins" {
  description = "CORS allowed origins (comma-separated). Passed to the ALLOWED_ORIGINS env var."
  type        = string
  default     = "*"
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated invocations (allUsers invoker). Set true for dev; false for prod."
  type        = bool
  default     = false
}
