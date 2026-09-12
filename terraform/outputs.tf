output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.main.name
}

output "cluster_location" {
  description = "GKE cluster region."
  value       = google_container_cluster.main.location
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.main.name
}

output "subnetwork_name" {
  description = "GKE subnet name."
  value       = google_compute_subnetwork.gke.name
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository resource name for application images."
  value       = google_artifact_registry_repository.images.name
}

output "cluster_endpoint" {
  description = "Public control-plane endpoint; access is restricted by master authorized networks."
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "github_actions_workload_identity_provider" {
  description = "Full Workload Identity Provider resource name for GitHub Actions authentication."
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "github_actions_deployer_service_account" {
  description = "Service account email used by the GitHub Actions deployment workflow."
  value       = google_service_account.github_actions_deployer.email
}

output "github_actions_terraform_service_account" {
  description = "Service account email used by the GitHub Actions Terraform workflow."
  value       = "${var.github_terraform_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

output "github_actions_image_repository" {
  description = "Artifact Registry image repository used by GitHub Actions."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/${google_artifact_registry_repository.images.repository_id}"
}
