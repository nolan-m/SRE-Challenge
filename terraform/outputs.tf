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

output "secondary_cluster_name" {
  description = "Secondary (failover) GKE cluster name."
  value       = google_container_cluster.secondary.name
}

output "secondary_cluster_location" {
  description = "Secondary (failover) GKE cluster region."
  value       = google_container_cluster.secondary.location
}

output "load_balancer_ip" {
  description = "Global external HTTP load balancer IP address serving both regions."
  value       = google_compute_global_address.lb.address
}

output "github_actions_workload_identity_provider" {
  description = "Full Workload Identity Provider resource name for GitHub Actions authentication."
  value       = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${var.github_workload_identity_pool_id}/providers/${var.github_workload_identity_provider_id}"
}

output "github_actions_deployer_service_account" {
  description = "Service account email used by the GitHub Actions deployment workflow."
  value       = "github-actions-deployer@${var.project_id}.iam.gserviceaccount.com"
}

output "github_actions_terraform_service_account" {
  description = "Service account email used by the GitHub Actions Terraform workflow."
  value       = "${var.github_terraform_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

output "github_actions_image_repository" {
  description = "Artifact Registry image repository used by GitHub Actions."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}/${google_artifact_registry_repository.images.repository_id}"
}
