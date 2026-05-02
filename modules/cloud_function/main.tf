# ---------------------------------------------------------------------------
# ingest-fn — Cloud Functions 2nd gen (Pub/Sub trigger)
#
# Consumes messages from flowterra-iot-ingress, parses MQTT payloads,
# writes live positions to Firestore, inserts into BigQuery, and
# triggers geofence alerts via FCM.
#
# Source is zipped from ../../ft-ingest-fn/ and stored in a GCS bucket.
# GitHub Actions re-deploys on push to main; Terraform manages infra only
# after the initial deploy.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Required APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "cloudfunctions" {
  project            = var.project_id
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service account for ingest-fn
# ---------------------------------------------------------------------------

resource "google_service_account" "ingest_fn" {
  project      = var.project_id
  account_id   = "flowterra-ingest-fn"
  display_name = "Flowterra ingest-fn Cloud Function"
}

# IAM changes can take ~60 s to propagate globally after SA creation.
# The Cloud Function build will fail if the SA isn't visible to IAM yet.
resource "time_sleep" "ingest_fn_sa_propagation" {
  create_duration = "60s"
  depends_on      = [google_service_account.ingest_fn]
}

resource "google_project_iam_member" "ingest_fn_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

resource "google_project_iam_member" "ingest_fn_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.ingest_fn.email}"
}

# Allow Pub/Sub service agent to create tokens for the ingest-fn SA
resource "google_project_iam_member" "ingest_fn_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Allow Pub/Sub service agent to invoke the Cloud Run service backing ingest-fn
resource "google_cloud_run_v2_service_iam_member" "pubsub_run_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.ingest_fn.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Allow Eventarc service agent to invoke the Cloud Run service backing ingest-fn.
# GCF2 Pub/Sub triggers route through Eventarc; the Eventarc SA must have
# run.invoker on the underlying Cloud Run service or deliveries fail with
# "unauthorized-client" in Cloud Function logs.
resource "google_cloud_run_v2_service_iam_member" "eventarc_run_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.ingest_fn.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}

# ---------------------------------------------------------------------------
# GCS bucket for function source zips
# ---------------------------------------------------------------------------

resource "google_storage_bucket" "fn_source" {
  project                     = var.project_id
  name                        = "flowterra-fn-source-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" }
  }

  labels = var.labels
}

# ---------------------------------------------------------------------------
# Zip and upload function source
# ---------------------------------------------------------------------------

data "archive_file" "ingest_fn_source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/ingest_fn_source.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

resource "google_storage_bucket_object" "ingest_fn_source" {
  name   = "ingest-fn-${data.archive_file.ingest_fn_source.output_sha256}.zip"
  bucket = google_storage_bucket.fn_source.name
  source = data.archive_file.ingest_fn_source.output_path
}

# ---------------------------------------------------------------------------
# Cloud Function 2nd gen
# ---------------------------------------------------------------------------

resource "google_cloudfunctions2_function" "ingest_fn" {
  project  = var.project_id
  name     = "flowterra-ingest-fn"
  location = var.region
  labels   = var.labels

  description = "Flowterra MQTT event stream processor: Firestore + BigQuery + FCM."

  build_config {
    runtime     = "python311"
    entry_point = "ingest_event"

    source {
      storage_source {
        bucket = google_storage_bucket.fn_source.name
        object = google_storage_bucket_object.ingest_fn_source.name
      }
    }
  }

  service_config {
    service_account_email = google_service_account.ingest_fn.email
    available_memory      = "256M"
    timeout_seconds       = 60
    min_instance_count    = var.min_instances
    max_instance_count    = 50

    environment_variables = {
      GCP_PROJECT_ID = var.project_id
      BQ_DATASET     = var.bq_dataset
      BQ_TABLE       = "location_events"
      ALERTS_TABLE   = "geofence_events"
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.pubsub_topic_id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.ingest_fn.email
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run,
    google_project_service.eventarc,
    time_sleep.ingest_fn_sa_propagation,
    google_project_iam_member.ingest_fn_firestore,
    google_project_iam_member.ingest_fn_bigquery,
    google_project_iam_member.ingest_fn_pubsub_subscriber,
  ]
}
