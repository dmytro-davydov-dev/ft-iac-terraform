variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the VM."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the VM. T4 GPUs are available in europe-west1-b."
  type        = string
  default     = "europe-west1-b"
}

variable "network" {
  description = "VPC network name for firewall rules and the instance."
  type        = string
  default     = "default"
}

variable "nodeodm_token_secret_id" {
  description = "Secret Manager secret ID for the NodeODM auth token."
  type        = string
  default     = "flowterra-nodeodm-token"
}

variable "cloud_run_sa_email" {
  description = "Service account email of the ft-api Cloud Run service, allowed to reach NodeODM on TCP 3000."
  type        = string
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
