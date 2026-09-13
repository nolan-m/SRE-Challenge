terraform {
  backend "gcs" {
    bucket = "nolan-sre-challenge-tfstate"
    prefix = "terraform/bootstrap-state"
  }
}