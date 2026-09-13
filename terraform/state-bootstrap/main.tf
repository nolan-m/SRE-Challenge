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

data "google_project" "current" {
  project_id = var.project_id
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
  for_each   = var.terraform_state_members
  bucket     = google_storage_bucket.terraform_state.name
  role       = "roles/storage.objectAdmin"
  member     = each.value
  depends_on = [google_service_account.deployer_managed]
}

resource "google_service_account" "terraform" {
  account_id   = var.terraform_service_account_id
  display_name = "GitHub Actions Terraform identity"
  project      = var.project_id
}

resource "google_service_account" "deployer_managed" {
  account_id   = var.deployer_service_account_id
  display_name = "GitHub Actions deployment identity"
  project      = var.project_id
}

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC identities from the trusted GitHub repository."
  project                   = data.google_project.current.number

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub OIDC"
  project                            = data.google_project.current.number

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/${var.github_branch}'"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account_iam_member" "terraform_impersonation" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repository}"
}

resource "google_service_account_iam_member" "deployer_impersonation" {
  service_account_id = google_service_account.deployer_managed.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repository}"
}

locals {
  terraform_roles = toset([
    "roles/artifactregistry.admin",
    "roles/compute.networkAdmin",
    "roles/container.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/monitoring.editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ])
}

resource "google_project_iam_member" "terraform_roles" {
  for_each = local.terraform_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer_managed.email}"
}
