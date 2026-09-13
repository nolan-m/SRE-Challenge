resource "google_project_iam_member" "github_actions_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:github-actions-deployer@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "github_actions_service_usage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:github-actions-deployer@${var.project_id}.iam.gserviceaccount.com"
}
