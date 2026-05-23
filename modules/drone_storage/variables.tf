variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "env" {
  description = "Environment name used as bucket name suffix (dev, demo, prod)."
  type        = string
}

variable "location" {
  description = "GCS bucket location."
  type        = string
  default     = "europe-west1"
}

variable "ft_api_sa_email" {
  description = "ft-api service account email — granted objectAdmin and signBlob for V4 signed URLs."
  type        = string
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
