terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

moved {
  from = google_storage_bucket_iam_member.terraform_backend
  to   = google_storage_bucket_iam_member.terraform_backend["serviceAccount:github-actions-deployer@nolan-sre-challenge.iam.gserviceaccount.com"]
}

resource "google_project_service" "bootstrap" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_storage_bucket" "terraform_state" {
  name                        = var.state_bucket_name
  project                     = var.project_id
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.bootstrap]
}

resource "google_storage_bucket_iam_member" "terraform_backend" {
  for_each = var.terraform_state_members
  bucket   = google_storage_bucket.terraform_state.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}