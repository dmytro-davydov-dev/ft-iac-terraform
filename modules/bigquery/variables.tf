variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "env" {
  description = "Environment name (dev, demo, prod). Used in the dataset description."
  type        = string
}

variable "dataset_id" {
  description = "BigQuery dataset ID (e.g. flowterra_dev)."
  type        = string
}

variable "bq_location" {
  description = "BigQuery dataset location. Use a multi-region (EU, US) or the same region as Cloud Run."
  type        = string
  default     = "EU"
}

variable "ingest_fn_sa_email" {
  description = "Service account email for ingest-fn (granted WRITER on the dataset)."
  type        = string
}

variable "ft_api_sa_email" {
  description = "Service account email for ft-api (granted READER on the dataset). Leave empty to skip."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
