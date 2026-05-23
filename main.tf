# ---------------------------------------------------------------------------
# Workspace → GCP project resolution
# Add new workspaces here before running `terraform workspace new <name>`.
# ---------------------------------------------------------------------------
locals {
  workspace_project = {
    dev  = "flowterra-dev"
    demo = "flowterra-demo" # demo environment — create GCP project before applying
    prod = "flowterra-prod" # create GCP project before applying prod workspace
  }

  project_id = local.workspace_project[terraform.workspace]

  # Common labels applied to every resource.
  common_labels = {
    project = "flowterra"
    env     = terraform.workspace
    managed = "terraform"
  }

  # Extra Firebase Auth authorized domains per workspace.
  # Extend after Cloud Run URLs are known (Phase 2).
  firebase_extra_domains = {
    dev  = []
    demo = []
    prod = []
  }

  # BigQuery dataset ID follows naming convention: flowterra_{env}
  bq_dataset_id = "flowterra_${terraform.workspace}"

  # Compute service account emails deterministically to avoid module cycles.
  # Both SAs are created as google_service_account resources below; using
  # interpolated emails here avoids circular dependencies with module.bigquery.
  ingest_fn_sa_email      = "flowterra-ingest-fn@${local.project_id}.iam.gserviceaccount.com"
  ft_api_sa_email         = "flowterra-ft-api@${local.project_id}.iam.gserviceaccount.com"
  otel_collector_sa_email = "flowterra-otel-collector@${local.project_id}.iam.gserviceaccount.com"
  nodeodm_vm_sa_email     = "flowterra-nodeodm-vm@${local.project_id}.iam.gserviceaccount.com"

  # ft-otel-collector: scale to zero in dev/demo, keep 1 warm in prod.
  otel_collector_min_instances = terraform.workspace == "prod" ? 1 : 0
}

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------
provider "google" {
  project = local.project_id
  region  = var.region
}

provider "google-beta" {
  project = local.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Child modules
# ---------------------------------------------------------------------------

module "firestore" {
  source = "./modules/firestore"

  project_id = local.project_id
  location   = var.firestore_location
  labels     = local.common_labels
}

module "pubsub" {
  source = "./modules/pubsub"

  project_id = local.project_id
  labels     = local.common_labels
}

module "firebase_auth" {
  source = "./modules/firebase_auth"

  project_id         = local.project_id
  authorized_domains = local.firebase_extra_domains[terraform.workspace]
}

module "secrets" {
  source = "./modules/secrets"

  project_id = local.project_id
  labels     = local.common_labels

  secrets = {
    # OBS Phase 1 — ft-otel-collector secrets.
    # Add secret versions out-of-band (never store values in Terraform state):
    #   gcloud secrets versions add flowterra-grafana-token --data-file=<(echo -n "$TOKEN")
    #   gcloud secrets versions add flowterra-grafana-otlp-endpoint --data-file=<(echo -n "$ENDPOINT")
    "flowterra-grafana-token" = {
      description           = "Grafana Cloud API token for OTLP export (ft-otel-collector)."
      automatic_replication = true
    }
    "flowterra-grafana-otlp-endpoint" = {
      description           = "Grafana Cloud OTLP endpoint host:port (ft-otel-collector)."
      automatic_replication = true
    }
    # Phase 5 — NodeODM VM token.
    #   gcloud secrets versions add flowterra-nodeodm-token --data-file=<(echo -n "$TOKEN")
    "flowterra-nodeodm-token" = {
      description           = "Auth token for the NodeODM Spot VM (flowterra-nodeodm-vm)."
      automatic_replication = true
    }
  }
}

# ---------------------------------------------------------------------------
# OBS Phase 1: OpenTelemetry Collector
# ---------------------------------------------------------------------------

# Dedicated service account for ft-otel-collector.
# Needs cloudtrace.agent to write spans to Cloud Trace.
# Needs secretmanager.secretAccessor on the two Grafana secrets.
resource "google_service_account" "otel_collector" {
  project      = local.project_id
  account_id   = "flowterra-otel-collector"
  display_name = "Flowterra ft-otel-collector"
  description  = "Workload identity for the ft-otel-collector Cloud Run service."
}

# Cloud Trace writer — required by the googlecloud exporter.
resource "google_project_iam_member" "otel_collector_trace_agent" {
  project = local.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${local.otel_collector_sa_email}"

  depends_on = [google_service_account.otel_collector]
}

# Secret accessor — GRAFANA_TOKEN
resource "google_secret_manager_secret_iam_member" "otel_collector_grafana_token" {
  project   = local.project_id
  secret_id = "flowterra-grafana-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.otel_collector_sa_email}"

  depends_on = [google_service_account.otel_collector, module.secrets]
}

# Secret accessor — GRAFANA_OTLP_ENDPOINT
resource "google_secret_manager_secret_iam_member" "otel_collector_grafana_endpoint" {
  project   = local.project_id
  secret_id = "flowterra-grafana-otlp-endpoint"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.otel_collector_sa_email}"

  depends_on = [google_service_account.otel_collector, module.secrets]
}

# ft-otel-collector Cloud Run service
module "otel_collector" {
  source = "./modules/otel_collector"

  project_id                 = local.project_id
  region                     = var.region
  service_account_email      = local.otel_collector_sa_email
  grafana_token_secret_id    = "flowterra-grafana-token"
  grafana_endpoint_secret_id = "flowterra-grafana-otlp-endpoint"
  min_instances              = local.otel_collector_min_instances
  labels                     = local.common_labels
  allow_unauthenticated      = terraform.workspace == "dev"

  depends_on = [
    google_service_account.otel_collector,
    google_project_iam_member.otel_collector_trace_agent,
    google_secret_manager_secret_iam_member.otel_collector_grafana_token,
    google_secret_manager_secret_iam_member.otel_collector_grafana_endpoint,
  ]
}

# ---------------------------------------------------------------------------
# Phase 4: IoT data pipeline
# ---------------------------------------------------------------------------

# Dedicated service account for ft-api (Cloud Run workload identity).
# Granted BigQuery READER on the analytics dataset (see module.bigquery).
# Also granted bigquery.jobUser at project level so it can run query jobs.
resource "google_service_account" "ft_api" {
  project      = local.project_id
  account_id   = "flowterra-ft-api"
  display_name = "Flowterra ft-api"
  description  = "Workload identity for the ft-api Cloud Run service."
}

# bigquery.jobUser — required to create and run BQ query jobs.
# READER on the dataset (in module.bigquery) grants data access; this grant
# enables the SA to actually submit queries.  Without it every BqClient call
# raises google.api_core.exceptions.Forbidden → 502 upstream_error.
resource "google_project_iam_member" "ft_api_bq_job_user" {
  project = local.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${local.ft_api_sa_email}"

  depends_on = [google_service_account.ft_api]
}

# BigQuery dataset + tables (deploy before ingest-fn so tables exist)
module "bigquery" {
  source = "./modules/bigquery"

  project_id         = local.project_id
  env                = terraform.workspace
  dataset_id         = local.bq_dataset_id
  bq_location        = var.bq_location
  ingest_fn_sa_email = local.ingest_fn_sa_email
  ft_api_sa_email    = local.ft_api_sa_email
  labels             = local.common_labels

  depends_on = [google_service_account.ft_api]
}

# ft-api Cloud Run service
module "cloud_run" {
  source = "./modules/cloud_run"

  project_id            = local.project_id
  region                = var.region
  service_account_email = local.ft_api_sa_email
  labels                = local.common_labels
  allow_unauthenticated = terraform.workspace == "dev"

  depends_on = [google_service_account.ft_api]
}

# ---------------------------------------------------------------------------
# Phase 5: Drone processing pipeline
# ---------------------------------------------------------------------------

# Drone GCS bucket + IAM for pre-signed upload URLs
module "drone_storage" {
  source = "./modules/drone_storage"

  project_id      = local.project_id
  env             = terraform.workspace
  ft_api_sa_email = local.ft_api_sa_email
  labels          = local.common_labels

  depends_on = [google_service_account.ft_api]
}

# NodeODM Spot VM — GPU-accelerated drone image processing
module "nodeodm_vm" {
  source = "./modules/nodeodm_vm"

  project_id              = local.project_id
  region                  = var.region
  cloud_run_sa_email      = local.ft_api_sa_email
  nodeodm_token_secret_id = "flowterra-nodeodm-token"
  labels                  = local.common_labels

  depends_on = [module.secrets]
}

# EMQX MQTT broker — Managed Instance Group, size=1
module "emqx_vm" {
  source = "./modules/emqx_vm"

  project_id   = local.project_id
  region       = var.region
  pubsub_topic = "flowterra-iot-ingress"
  labels       = local.common_labels
}

# ingest-fn Cloud Function — consumes flowterra-iot-ingress → BQ + Firestore
module "cloud_function" {
  source = "./modules/cloud_function"

  project_id      = local.project_id
  region          = var.region
  source_dir      = "${path.root}/../ft-ingest-fn"
  pubsub_topic_id = module.pubsub.topic_ids["iot_ingress"]
  bq_dataset      = local.bq_dataset_id
  labels          = local.common_labels

  # Implicit ordering: cloud_function references pubsub topic from module.pubsub.
  # BigQuery tables must exist before ingest-fn starts receiving events, but
  # Terraform can create both in parallel — BQ finishes first in practice.
}
