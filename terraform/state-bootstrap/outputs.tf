output "state_bucket_name" {
  description = "GCS bucket used by the main Terraform backend."
  value       = google_storage_bucket.terraform_state.name
}

output "terraform_service_account" {
  value = google_service_account.terraform.email
}

output "deployer_service_account" {
  value = google_service_account.deployer_managed.email
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_actions.name
}