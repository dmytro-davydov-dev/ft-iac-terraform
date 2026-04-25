# ---------------------------------------------------------------------------
# Secret Manager
#
# This module creates Secret Manager secret *resources* (the container +
# metadata).  Secret *versions* (the actual values) are added out-of-band
# by developers or CI/CD — never stored in Terraform state.
#
# To add a secret, add an entry to the `secrets` variable in main.tf.
# Example (in root main.tf module block):
#
#   module "secrets" {
#     source     = "./modules/secrets"
#     project_id = local.project_id
#     labels     = local.common_labels
#     secrets = {
#       api_key = {
#         description           = "Third-party API key for drone telemetry ingestion"
#         automatic_replication = true
#       }
#     }
#   }
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "secrets" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key
  labels    = var.labels

  replication {
    dynamic "auto" {
      for_each = each.value.automatic_replication ? [1] : []
      content {}
    }

    dynamic "user_managed" {
      for_each = each.value.automatic_replication ? [] : [1]
      content {
        replicas {
          location = "us-central1"
        }
        replicas {
          location = "us-east1"
        }
      }
    }
  }
}
