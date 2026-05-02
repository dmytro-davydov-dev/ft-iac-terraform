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

  # Compute the ingest-fn SA email deterministically to avoid a module cycle.
  # (module.bigquery needs it, module.cloud_function creates it — referencing
  # the output would create a cycle.)
  ingest_fn_sa_email = "flowterra-ingest-fn@${local.project_id}.iam.gserviceaccount.com"
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
}

# ---------------------------------------------------------------------------
# Phase 4: IoT data pipeline
# ---------------------------------------------------------------------------

# BigQuery dataset + tables (deploy before ingest-fn so tables exist)
module "bigquery" {
  source = "./modules/bigquery"

  project_id         = local.project_id
  env                = terraform.workspace
  dataset_id         = local.bq_dataset_id
  bq_location        = var.bq_location
  ingest_fn_sa_email = local.ingest_fn_sa_email
  labels             = local.common_labels
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
