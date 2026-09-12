resource "google_service_account" "github_actions_deployer" {
  account_id   = var.github_deployer_service_account_id
  display_name = "GitHub Actions deployment identity"
  project      = var.project_id
}

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = var.github_workload_identity_pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC identities from the trusted GitHub repository."
  project                   = var.project_id

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_workload_identity_provider_id
  display_name                       = "GitHub OIDC"
  project                            = var.project_id

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.workflow"   = "assertion.workflow"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/${var.github_branch}'"
}

resource "google_service_account_iam_member" "github_actions_impersonation" {
  service_account_id = google_service_account.github_actions_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "github_actions_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_actions_deployer.email}"
}

resource "google_project_iam_member" "github_actions_service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.github_actions_deployer.email}"
}