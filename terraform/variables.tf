variable "project_id" {
  description = "GCP project hosting the cluster and network."
  type        = string
}

variable "region" {
  description = "GCP region for the regional Autopilot cluster."
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "nolan-sre"
}

variable "network_name" {
  description = "VPC network name."
  type        = string
  default     = "nolan-sre-vpc"
}

variable "subnetwork_name" {
  description = "GKE subnet name."
  type        = string
  default     = "nolan-sre-gke"
}

variable "artifact_registry_repository" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "nolan-sre"
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate through Workload Identity Federation, in OWNER/REPOSITORY form."
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch allowed to deploy through Workload Identity Federation."
  type        = string
  default     = "main"
}

variable "github_workload_identity_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions."
  type        = string
  default     = "github-actions"
}

variable "github_workload_identity_provider_id" {
  description = "Workload Identity Provider ID for GitHub Actions."
  type        = string
  default     = "github-oidc"
}

variable "github_deployer_service_account_id" {
  description = "Service account ID used by the GitHub Actions deployment workflow."
  type        = string
  default     = "github-actions-deployer"
}

variable "github_terraform_service_account_id" {
  description = "Service account ID used by the GitHub Actions Terraform workflow."
  type        = string
  default     = "github-actions-terraform"
}

variable "nodes_cidr" {
  description = "Primary subnet range reserved for GKE infrastructure."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range reserved for Pod IPs."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range reserved for Service IPs."
  type        = string
  default     = "10.30.0.0/20"
}

variable "pods_secondary_range_name" {
  description = "Name of the Pod secondary range."
  type        = string
  default     = "nolan-sre-pods"
}

variable "services_secondary_range_name" {
  description = "Name of the Service secondary range."
  type        = string
  default     = "nolan-sre-services"
}

variable "master_ipv4_cidr" {
  description = "Non-overlapping RFC1918 /28 range for the private control-plane peering."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "Trusted CIDRs allowed to reach the public control-plane endpoint. Do not use 0.0.0.0/0."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0 && alltrue([for network in var.master_authorized_networks : network.cidr_block != "0.0.0.0/0"])
    error_message = "Provide at least one trusted control-plane CIDR and never authorize 0.0.0.0/0."
  }
}

variable "release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion."
  type        = bool
  default     = true
}

variable "notification_emails" {
  description = "Optional email addresses that receive Cloud Monitoring alert notifications."
  type        = set(string)
  default     = []
}

variable "maintenance_start_time" {
  description = "RFC3339 start time for the weekly maintenance window, in UTC."
  type        = string
  default     = "2026-01-04T02:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 end time for the weekly maintenance window, in UTC."
  type        = string
  default     = "2026-01-04T06:00:00Z"
}

variable "maintenance_recurrence" {
  description = "RFC5545 recurrence for the maintenance window."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SU"
}

variable "secondary_region" {
  description = "GCP region for the secondary (failover) regional Autopilot cluster."
  type        = string
  default     = "us-east1"
}

variable "secondary_cluster_name" {
  description = "Secondary (failover) GKE cluster name."
  type        = string
  default     = "nolan-sre-secondary"
}

variable "secondary_subnetwork_name" {
  description = "Secondary GKE subnet name."
  type        = string
  default     = "nolan-sre-gke-secondary"
}

variable "secondary_nodes_cidr" {
  description = "Primary subnet range reserved for secondary-region GKE infrastructure."
  type        = string
  default     = "10.11.0.0/20"
}

variable "secondary_pods_cidr" {
  description = "Secondary range reserved for Pod IPs in the secondary region."
  type        = string
  default     = "10.21.0.0/16"
}

variable "secondary_services_cidr" {
  description = "Secondary range reserved for Service IPs in the secondary region."
  type        = string
  default     = "10.31.0.0/20"
}

variable "secondary_pods_secondary_range_name" {
  description = "Name of the Pod secondary range in the secondary region."
  type        = string
  default     = "nolan-sre-pods-secondary"
}

variable "secondary_services_secondary_range_name" {
  description = "Name of the Service secondary range in the secondary region."
  type        = string
  default     = "nolan-sre-services-secondary"
}

variable "secondary_master_ipv4_cidr" {
  description = "Non-overlapping RFC1918 /28 range for the secondary cluster's private control-plane peering."
  type        = string
  default     = "172.16.0.16/28"
}

variable "neg_name" {
  description = "Name of the standalone Network Endpoint Group created by the annotated Kubernetes Service in both clusters."
  type        = string
  default     = "nolan-sre-neg"
}

variable "enable_load_balancer_backends" {
  description = "Wire the standalone NEGs into the load balancer's backend service. Leave false until the Kubernetes manifest has been deployed to both clusters and the NEGs exist, then set true and re-apply."
  type        = bool
  default     = false
}
