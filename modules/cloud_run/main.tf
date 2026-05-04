# ---------------------------------------------------------------------------
# Cloud Run service — ft-api
#
# This module provisions the Cloud Run service resource and its IAM policy.
# The container image is built and deployed by GitHub Actions
# (see .github/workflows/deploy-ft-api.yml); Terraform manages only the
# service definition and IAM bindings.
#
# /health is intentionally left unauthenticated for Cloud Run probes.
# All other routes require a valid Firebase JWT — enforced at app level.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "ft_api" {
  project  = var.project_id
  name     = "ft-api"
  location = var.region
  labels   = var.labels

  template {
    labels          = var.labels
    service_account = var.service_account_email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      # Image is updated on each GitHub Actions deploy; Terraform sets the
      # initial placeholder — GH Actions takes over after first deploy.
      image = var.image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true # scale to zero — only bill when handling requests
      }

      ports {
        container_port = 8080
      }

      env {
        name  = "ALLOWED_ORIGINS"
        value = var.allowed_origins
      }
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — Cloud Run Invoker
# ---------------------------------------------------------------------------

# Allow unauthenticated access to /health only via NEG or directly in dev.
# All other routes are protected by the require_auth middleware.
# For a stricter setup, remove this and route /health through an
# authenticated service identity in the CI pipeline.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.ft_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
