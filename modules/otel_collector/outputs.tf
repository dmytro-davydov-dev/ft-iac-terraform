output "service_url" {
  description = "The HTTPS URL of the deployed ft-otel-collector Cloud Run service."
  value       = google_cloud_run_v2_service.otel_collector.uri
}

output "service_name" {
  description = "Cloud Run service name (flowterra-otel-collector)."
  value       = google_cloud_run_v2_service.otel_collector.name
}

output "grpc_otlp_endpoint" {
  description = "gRPC OTLP endpoint for instrumented services (strip https://, port implicit 443 on Cloud Run)."
  value       = replace(google_cloud_run_v2_service.otel_collector.uri, "https://", "")
}
