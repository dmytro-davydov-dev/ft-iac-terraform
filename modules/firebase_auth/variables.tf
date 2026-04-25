variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "authorized_domains" {
  description = <<-EOT
    Additional domains authorized for Firebase Auth redirects, beyond the
    default localhost / <project>.firebaseapp.com / <project>.web.app trio.
    Typical additions: Cloud Run service URL, custom apex domain.
  EOT
  type        = list(string)
  default     = []
}
