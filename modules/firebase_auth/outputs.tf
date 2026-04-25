output "firebase_project_id" {
  description = "Firebase-linked GCP project ID."
  value       = google_firebase_project.default.project
}

output "identity_platform_name" {
  description = "Resource name of the Identity Platform (Firebase Auth) config."
  value       = google_identity_platform_config.auth.name
}

output "authorized_domains" {
  description = "Full list of domains authorized for Firebase Auth redirects (includes defaults + extras)."
  value       = google_identity_platform_config.auth.authorized_domains
}
