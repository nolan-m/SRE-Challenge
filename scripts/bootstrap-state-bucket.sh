#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-}"
BUCKET_NAME="${STATE_BUCKET_NAME:-}"
BUCKET_LOCATION="${STATE_BUCKET_LOCATION:-US}"

usage() {
  cat <<EOF
Usage: $0 --project-id PROJECT_ID [options]

Options:
  --project-id ID       GCP project ID (required unless PROJECT_ID is set)
  --bucket-name NAME    State bucket name (default: <project-id>-tfstate)
  --location LOCATION   Bucket location (default: US)
  -h, --help            Show this help

This script creates the state bucket when it does not exist and enables versioning.
It does not initialize Terraform state, import resources, or delete anything.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --project-id" >&2; exit 2; }
      PROJECT_ID="$2"
      shift 2
      ;;
    --bucket-name)
      [[ $# -ge 2 ]] || { echo "Missing value for --bucket-name" >&2; exit 2; }
      BUCKET_NAME="$2"
      shift 2
      ;;
    --location)
      [[ $# -ge 2 ]] || { echo "Missing value for --location" >&2; exit 2; }
      BUCKET_LOCATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$PROJECT_ID" ]] || {
  echo "Set PROJECT_ID or pass --project-id." >&2
  exit 1
}
command -v gcloud >/dev/null || { echo "gcloud is required." >&2; exit 1; }

if [[ -z "$BUCKET_NAME" ]]; then
  BUCKET_NAME="${PROJECT_ID}-tfstate"
fi

if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "State bucket already exists: gs://${BUCKET_NAME}"
else
  echo "Creating state bucket: gs://${BUCKET_NAME}"
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="$PROJECT_ID" \
    --location="$BUCKET_LOCATION" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

echo "Enabling bucket versioning..."
gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning

echo "State bucket is ready: gs://${BUCKET_NAME}"
