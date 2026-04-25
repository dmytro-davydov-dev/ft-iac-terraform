variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "labels" {
  description = "Labels to apply to Pub/Sub resources."
  type        = map(string)
  default     = {}
}

variable "message_retention_duration" {
  description = "How long undelivered messages are retained (e.g. '604800s' = 7 days)."
  type        = string
  default     = "604800s"
}

variable "ack_deadline_seconds" {
  description = "Default subscription ack deadline in seconds."
  type        = number
  default     = 60
}
