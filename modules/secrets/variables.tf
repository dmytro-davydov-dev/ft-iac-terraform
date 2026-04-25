variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "labels" {
  description = "Labels to apply to Secret Manager secrets."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Map of secret definitions.  Each entry:
      name        — GCP secret resource name (follows flowterra-* convention)
      description — human-readable description
      automatic_replication — set to true for multi-region automatic replication
  EOT
  type = map(object({
    description            = string
    automatic_replication  = optional(bool, true)
  }))
  default = {}
}
