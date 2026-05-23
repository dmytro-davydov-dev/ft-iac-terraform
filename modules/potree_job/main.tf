# ---------------------------------------------------------------------------
# PotreeConverter Cloud Run Job — flowterra-potree-converter
#
# Converts ODM LAS point cloud from GCS to Potree octree tiles and uploads
# them back to GCS. Triggered by the ODM status poller (ft-api) via:
#
#   gcloud run jobs execute flowterra-potree-converter \
#     --args="--capture-id=<uuid>" --region=europe-west1
#
# Job flow:
#   1. Download captures/{capture_id}/processed/odm_pointcloud.las from GCS
#   2. Run PotreeConverter  input.las -o /tmp/tiles --output-format LAZ
#   3. Upload /tmp/tiles/ → GCS captures/{capture_id}/tiles/
#   4. PATCH Supabase captures: status='ready', tiles_gcs_prefix, metadata.gsd_cm
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Required APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Artifact Registry — shared Docker repo for drone pipeline images
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository" "drone" {
  project       = var.project_id
  location      = var.region
  repository_id = "drone"
  format        = "DOCKER"
  description   = "Docker images for the Flowterra drone processing pipeline."

  depends_on = [google_project_service.artifactregistry]
}

# ---------------------------------------------------------------------------
# Service account for the Cloud Run Job
# ---------------------------------------------------------------------------

resource "google_service_account" "potree_job" {
  project      = var.project_id
  account_id   = "flowterra-potree-job"
  display_name = "Flowterra PotreeConverter Job"
  description  = "Workload identity for the flowterra-potree-converter Cloud Run Job."
}

# GCS object admin on the drone bucket — download LAS, upload tiles
resource "google_storage_bucket_iam_member" "potree_job_storage" {
  bucket = var.drone_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.potree_job.email}"
}

# Read Supabase secrets from Secret Manager
resource "google_project_iam_member" "potree_job_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.potree_job.email}"
}

# Write job logs to Cloud Logging
resource "google_project_iam_member" "potree_job_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.potree_job.email}"
}

# Allow ft-api SA to trigger this job (run.jobs.run)
resource "google_cloud_run_v2_job_iam_member" "ft_api_runner" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.potree_converter.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${var.ft_api_sa_email}"
}

# ---------------------------------------------------------------------------
# Cloud Run Job
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "potree_converter" {
  project  = var.project_id
  name     = "flowterra-potree-converter"
  location = var.region
  labels   = var.labels

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = google_service_account.potree_job.email
      max_retries     = 2
      timeout         = "600s"

      containers {
        image = var.image

        resources {
          limits = {
            cpu    = "4"
            memory = "8Gi"
          }
        }

        env {
          name  = "DRONE_BUCKET"
          value = var.drone_bucket_name
        }

        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }

        env {
          name = "SUPABASE_URL"
          value_source {
            secret_key_ref {
              secret  = var.supabase_url_secret_id
              version = "latest"
            }
          }
        }

        env {
          name = "SUPABASE_SERVICE_KEY"
          value_source {
            secret_key_ref {
              secret  = var.supabase_service_key_secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.run,
    google_service_account.potree_job,
    google_project_iam_member.potree_job_secret_accessor,
    google_project_iam_member.potree_job_log_writer,
  ]
}
