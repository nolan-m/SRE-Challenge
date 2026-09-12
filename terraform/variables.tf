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
