# ---------------------------------------------------------------------------
# Firestore — Native mode, default database
#
# Firestore in Native mode is required for Firebase SDKs and real-time
# listeners. The default database "(default)" is used by Firebase Auth
# automatically when security rules are deployed.
# ---------------------------------------------------------------------------

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.location
  type        = "FIRESTORE_NATIVE"

  # Prevent accidental deletion of the primary database.
  deletion_policy = "DELETE"

  # Point-in-time recovery keeps 7 days of change history.
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
}
