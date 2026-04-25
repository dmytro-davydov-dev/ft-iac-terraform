#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — one-time setup before the first `terraform init`
#
# Run this ONCE per environment before using Terraform.
# The GCS bucket for remote state must exist before `terraform init` can
# configure the backend.
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh dev      # provision state bucket for DEV workspace
#   ./bootstrap.sh demo     # provision state bucket for DEMO workspace
#   ./bootstrap.sh prod     # provision state bucket for PROD workspace (future)
# =============================================================================
set -euo pipefail

ENV="${1:-dev}"

case "$ENV" in
  dev)
    PROJECT_ID="flowterra-dev"
    ;;
  demo)
    PROJECT_ID="flowterra-demo"
    ;;
  prod)
    PROJECT_ID="flowterra-prod"
    ;;
  *)
    echo "ERROR: Unknown environment '$ENV'. Valid values: dev | demo | prod"
    exit 1
    ;;
esac

BUCKET_NAME="flowterra-terraform-state"
REGION="us-central1"

echo "=== Bootstrap: Terraform state bucket for '$ENV' (project: $PROJECT_ID) ==="

# Set active project
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo ">>> Enabling APIs..."
gcloud services enable \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  pubsub.googleapis.com \
  firestore.googleapis.com \
  firebase.googleapis.com \
  firebaserules.googleapis.com \
  identitytoolkit.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID"

# Create GCS bucket (skip if already exists)
if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
  echo ">>> Bucket gs://$BUCKET_NAME already exists — skipping creation."
else
  echo ">>> Creating bucket gs://$BUCKET_NAME in $REGION..."
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# Enable versioning (required for state locking + recovery)
echo ">>> Enabling versioning on gs://$BUCKET_NAME..."
gcloud storage buckets update "gs://$BUCKET_NAME" \
  --versioning

# Label the bucket
echo ">>> Labelling bucket..."
gcloud storage buckets update "gs://$BUCKET_NAME" \
  --update-labels="project=flowterra,env=$ENV,managed=terraform"

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  cd iac-terraform/"
echo "  terraform init"
echo "  terraform workspace new dev   # first time only"
echo "  terraform workspace select dev"
echo "  terraform plan"
echo "  terraform apply"
