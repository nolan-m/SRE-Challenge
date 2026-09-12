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
