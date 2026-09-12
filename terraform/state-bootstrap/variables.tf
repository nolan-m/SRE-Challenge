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

variable "terraform_service_account" {
  description = "Service account allowed to read and write the Terraform state bucket."
  type        = string
}