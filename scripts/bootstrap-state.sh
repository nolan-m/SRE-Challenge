#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_DIR="$REPOSITORY_ROOT/terraform/state-bootstrap"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
PROJECT_ID="${PROJECT_ID:-}"
STATE_BUCKET_NAME="${STATE_BUCKET_NAME:-}"
STATE_MEMBERS=()

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --project-id ID       GCP project ID (required unless PROJECT_ID is set)
  --state-bucket NAME   State bucket name (default: <project-id>-tfstate)
  --state-member MEMBER Additional IAM member (repeatable)
  -h, --help            Show this help

The authenticated gcloud account is added as a state bucket member automatically.
The GitHub Actions deployer service account is also added automatically.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --project-id" >&2; exit 2; }
      PROJECT_ID="$2"
      shift 2
      ;;
    --state-bucket)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-bucket" >&2; exit 2; }
      STATE_BUCKET_NAME="$2"
      shift 2
      ;;
    --state-member)
      [[ $# -ge 2 ]] || { echo "Missing value for --state-member" >&2; exit 2; }
      STATE_MEMBERS+=("$2")
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
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }
command -v terraform >/dev/null || { echo "terraform is required." >&2; exit 1; }

if [[ -z "$STATE_BUCKET_NAME" ]]; then
  STATE_BUCKET_NAME="${PROJECT_ID}-tfstate"
fi

ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
[[ -n "$ACTIVE_ACCOUNT" && "$ACTIVE_ACCOUNT" != "(unset)" ]] || {
  echo "No active gcloud account. Run gcloud auth login first." >&2
  exit 1
}

STATE_MEMBERS+=("user:${ACTIVE_ACCOUNT}")
STATE_MEMBERS+=("serviceAccount:github-actions-deployer@${PROJECT_ID}.iam.gserviceaccount.com")

MEMBERS_JSON="$(printf '%s\n' "${STATE_MEMBERS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')"

echo "Initializing state bucket Terraform..."
terraform -chdir="$BOOTSTRAP_DIR" init -input=false

echo "Applying state bucket and IAM configuration..."
terraform -chdir="$BOOTSTRAP_DIR" apply -input=false -auto-approve \
  -var="project_id=$PROJECT_ID" \
  -var="state_bucket_name=$STATE_BUCKET_NAME" \
  -var="terraform_state_members=$MEMBERS_JSON"

echo "Initializing the main Terraform backend. Review the migration prompt..."
terraform -chdir="$TERRAFORM_DIR" init -migrate-state

echo "Remote Terraform state is configured in gs://${STATE_BUCKET_NAME}/terraform/state."