output "database_name" {
  description = "Firestore database name."
  value       = google_firestore_database.default.name
}

output "database_id" {
  description = "Full resource ID of the Firestore database."
  value       = google_firestore_database.default.id
}
