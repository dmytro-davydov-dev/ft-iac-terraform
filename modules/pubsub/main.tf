# ---------------------------------------------------------------------------
# Pub/Sub — topics and push subscriptions
#
# Topics follow the flowterra-* naming convention.
# Add new topics to local.topics; subscriptions are generated automatically.
# ---------------------------------------------------------------------------

locals {
  # Define every topic here.  The map key is a logical name used in outputs;
  # the value is the GCP topic name (must start with flowterra-).
  topics = {
    job_created     = "flowterra-job-created"
    job_updated     = "flowterra-job-updated"
    drone_telemetry = "flowterra-drone-telemetry"
    iot_ingress     = "flowterra-iot-ingress"   # FLO-9: EMQX → ingest-fn bridge (Phase 4)
  }

  # Pull subscriptions: one per topic, for Cloud Run worker.
  # Adjust or add push subscriptions per topic in a later iteration.
  subscriptions = {
    for k, topic_name in local.topics :
    k => {
      topic = topic_name
      name  = "${topic_name}-sub"
    }
  }
}

resource "google_pubsub_topic" "topics" {
  for_each = local.topics

  project = var.project_id
  name    = each.value
  labels  = var.labels

  message_retention_duration = var.message_retention_duration
}

resource "google_pubsub_subscription" "subscriptions" {
  for_each = local.subscriptions

  project = var.project_id
  name    = each.value.name
  topic   = google_pubsub_topic.topics[each.key].name
  labels  = var.labels

  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration

  # Dead-letter policy: after 5 failed deliveries, route to a dead-letter topic.
  # Uncomment when flowterra-dead-letter topic is added.
  # dead_letter_policy {
  #   dead_letter_topic     = "projects/${var.project_id}/topics/flowterra-dead-letter"
  #   max_delivery_attempts = 5
  # }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}
