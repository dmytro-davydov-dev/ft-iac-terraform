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
    project   = "flowterra"
    env       = terraform.workspace
    managed   = "terraform"
  }

  # Extra Firebase Auth authorized domains per workspace.
  # Extend after Cloud Run URLs are known (Phase 2).
  firebase_extra_domains = {
    dev  = []
    demo = []
    prod = []
  }
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

  project_id         = local.project_id
  location           = var.firestore_location
  labels             = local.common_labels
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
