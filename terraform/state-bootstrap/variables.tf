variable "project_id" {
  description = "GCP project that owns the Terraform state bucket."
  type        = string
}

variable "region" {
  description = "Default GCP provider region."
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Location for the Terraform state bucket."
  type        = string
  default     = "US"
}

variable "state_bucket_name" {
  description = "Globally unique GCS bucket name for Terraform state."
  type        = string
  default     = "nolan-sre-challenge-tfstate"
}

variable "terraform_state_members" {
  description = "IAM members allowed to read and write Terraform state, such as serviceAccount:... or user:... ."
  type        = set(string)
  default     = []
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate through Workload Identity Federation."
  type        = string
}

variable "github_branch" {
  description = "GitHub branch allowed to use the Terraform identity."
  type        = string
  default     = "main"
}

variable "workload_identity_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions."
  type        = string
  default     = "github-actions"
}

variable "workload_identity_provider_id" {
  description = "Workload Identity Provider ID for GitHub Actions."
  type        = string
  default     = "github-oidc"
}

variable "terraform_service_account_id" {
  description = "Service account ID used by the Terraform workflow."
  type        = string
  default     = "github-actions-terraform"
}

variable "deployer_service_account_id" {
  description = "Service account ID used by the application deployment workflow."
  type        = string
  default     = "github-actions-deployer"
}