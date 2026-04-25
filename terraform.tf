terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # GCS remote state backend.
  # Bucket must be created BEFORE running `terraform init` — see bootstrap.sh.
  # Workspace-aware: state files are stored at:
  #   gs://flowterra-terraform-state/env:<workspace>/default.tfstate
  backend "gcs" {
    bucket = "flowterra-terraform-state"
    prefix = "terraform/state"
  }
}
