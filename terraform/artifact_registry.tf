data "google_project" "current" {
  project_id = var.project_id
}

removed {
  from = google_artifact_registry_repository_iam_member.gke_pull

  lifecycle {
    destroy = false
  }
}

removed {
  from = google_artifact_registry_repository_iam_member.github_actions_push

  lifecycle {
    destroy = false
  }
}

resource "google_project_iam_member" "gke_pull" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = var.artifact_registry_repository
  description   = "Container images for the nolan-sre application."
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "github_actions_push" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions_deployer.email}"
}