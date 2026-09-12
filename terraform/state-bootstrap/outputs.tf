output "state_bucket_name" {
  description = "GCS bucket used by the main Terraform backend."
  value       = google_storage_bucket.terraform_state.name
}