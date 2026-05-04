# ---------------------------------------------------------------------------
# Cloud Run service — ft-otel-collector (flowterra-otel-collector)
#
# Central fan-out hub: receives all OTLP telemetry from every Flowterra
# service and routes it to Grafana Cloud (Tempo/Mimir/Loki) and GCP Cloud
# Trace simultaneously.
#
# OTLP gRPC  → port 4317 (Cloud Run h2c ingress)
# OTLP HTTP  → port 4318 (internal only; same container)
# Health     → port 13133 via health_check extension (used by liveness probe)
#
# Container image is built and pushed by GitHub Actions
# (see .github/workflows/deploy-ft-otel-collector.yml); Terraform manages
# only the service definition, IAM, and secret bindings.
#
# Tail-based sampling decision is made locally per instance — valid for a
# single-instance setup (dev/demo min_instances=0 with cold-start tolerance,
# prod min_instances=1). For multi-instance fan-out, replace with a separate
# tail-sampling collector tier.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "otel_collector" {
  project  = var.project_id
  name     = "flowterra-otel-collector"
  location = var.region
  labels   = var.labels

  template {
    labels          = var.labels
    service_account = var.service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # Keep CPU allocated while idle so tail-sampling buffers stay warm.
        # Flip to true in dev if cost is a concern (adds cold-start tail).
        cpu_idle = false
      }

      # gRPC OTLP — primary Cloud Run ingress port (h2c = HTTP/2 cleartext,
      # required for gRPC on Cloud Run without TLS termination in-container).
      ports {
        name           = "h2c"
        container_port = 4317
      }

      # ---------------------------------------------------------------------------
      # Secrets — mounted as environment variables
      # ---------------------------------------------------------------------------
      env {
        name = "GRAFANA_TOKEN"
        value_source {
          secret_key_ref {
            secret  = var.grafana_token_secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "GRAFANA_OTLP_ENDPOINT"
        value_source {
          secret_key_ref {
            secret  = var.grafana_endpoint_secret_id
            version = "latest"
          }
        }
      }

      # Cloud Run injects GOOGLE_CLOUD_PROJECT automatically for Workload
      # Identity; the googlecloud exporter reads it from the metadata server.
      # Explicit var here for clarity and local testing.
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }

      # ---------------------------------------------------------------------------
      # Probes
      # ---------------------------------------------------------------------------

      # Startup probe: wait up to 30 s for the health_check extension to come up.
      startup_probe {
        http_get {
          path = "/health"
          port = 13133
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 6
        timeout_seconds       = 3
      }

      # Liveness probe: restart the container if it stops responding.
      liveness_probe {
        http_get {
          path = "/health"
          port = 13133
        }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 5
      }
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — Cloud Run Invoker
# ---------------------------------------------------------------------------

# In dev, allow unauthenticated calls so grpcurl smoke tests work without
# a service account token. In demo/prod, remove allUsers and require a
# signed JWT from the calling service (Workload Identity).
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.otel_collector.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
