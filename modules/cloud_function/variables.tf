variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Function and GCS bucket."
  type        = string
  default     = "europe-west1"
}

variable "source_dir" {
  description = "Local path to the ft-ingest-fn source directory (archived and uploaded to GCS)."
  type        = string
  default     = "../../ft-ingest-fn"
}

variable "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic that triggers the function (e.g. projects/PROJECT/topics/TOPIC)."
  type        = string
}

variable "bq_dataset" {
  description = "BigQuery dataset ID that ingest-fn writes to."
  type        = string
}

variable "min_instances" {
  description = "Minimum number of function instances. Set to 1 to avoid cold-start latency (~$7/mo)."
  type        = number
  default     = 0
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
