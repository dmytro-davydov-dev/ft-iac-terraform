# ---------------------------------------------------------------------------
# Workspace → GCP project mapping
# Each Terraform workspace maps 1:1 to its own GCP project.
#
#   dev  → flowterra-dev     (DEV — migrated from flowterra, project to be created)
#   demo → flowterra-demo    (DEMO)
#   prod → flowterra-prod    (to be created before MVP launch)
#
# Never set project_id directly — always derive it from the workspace locals.
# ---------------------------------------------------------------------------

variable "region" {
  description = "Default GCP region for all regional resources."
  type        = string
  default     = "us-central1"
}

variable "firestore_location" {
  description = "Multi-region location for Firestore (nam5 = US, eur3 = EU)."
  type        = string
  default     = "nam5"
}
