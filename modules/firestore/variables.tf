variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Firestore multi-region location (nam5, eur3)."
  type        = string
  default     = "nam5"
}

variable "labels" {
  description = "Labels to apply to Firestore resources."
  type        = map(string)
  default     = {}
}
