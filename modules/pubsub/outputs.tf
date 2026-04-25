output "topic_ids" {
  description = "Map of logical name → full Pub/Sub topic resource ID."
  value       = { for k, t in google_pubsub_topic.topics : k => t.id }
}

output "subscription_ids" {
  description = "Map of logical name → full Pub/Sub subscription resource ID."
  value       = { for k, s in google_pubsub_subscription.subscriptions : k => s.id }
}
