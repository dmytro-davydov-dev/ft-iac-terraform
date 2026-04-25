# ---------------------------------------------------------------------------
# Firebase Auth — Phase 1 Foundation
#
# Terraform manages:
#   1. google_firebase_project  — links the GCP project to Firebase
#   2. google_identity_platform_config — enables Firebase Auth (Identity Toolkit)
#      with Email/Password as the sole sign-in provider for MVP.
#
# NOT managed here (Firebase console or firebase-tools CLI):
#   - Email template branding
#   - reCAPTCHA / advanced abuse prevention
#   - Multi-factor authentication (post-MVP)
#
# Prerequisites (handled by bootstrap.sh):
#   gcloud services enable identitytoolkit.googleapis.com --project=<id>
# ---------------------------------------------------------------------------

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Identity Platform config — enables Firebase Auth and configures sign-in.
# Depends on the Firebase project link above.
# ---------------------------------------------------------------------------
resource "google_identity_platform_config" "auth" {
  provider = google-beta
  project  = var.project_id

  # Email / password is the sole sign-in provider for MVP.
  sign_in {
    email {
      enabled           = true
      password_required = true
    }
    # Prevent multiple accounts with the same email address.
    allow_duplicate_emails = false
  }

  # Explicitly list all domains that may initiate Firebase Auth redirects.
  # Always includes the two Firebase-provisioned subdomains + localhost.
  # Additional domains (e.g. custom apex domain) are passed via var.authorized_domains.
  authorized_domains = concat(
    [
      "localhost",
      "${var.project_id}.firebaseapp.com",
      "${var.project_id}.web.app",
    ],
    var.authorized_domains
  )

  lifecycle {
    # Prevent accidental destruction — would lock all users out immediately.
    prevent_destroy = true
  }

  depends_on = [google_firebase_project.default]
}
