variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the MIG and health check."
  type        = string
  default     = "europe-west1"
}

variable "network" {
  description = "VPC network name for firewall rules and the instance template."
  type        = string
  default     = "default"
}

variable "pubsub_topic" {
  description = "Pub/Sub topic name (not full path) the MQTT bridge publishes to."
  type        = string
  default     = "flowterra-iot-ingress"
}

variable "labels" {
  description = "Labels applied to all resources in this module."
  type        = map(string)
  default     = {}
}
