#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
VAR_FILE="environments/dev.tfvars"
MASTER_AUTHORIZED_IP="${MASTER_AUTHORIZED_IP:-}"
MASTER_AUTHORIZED_DISPLAY_NAME="${MASTER_AUTHORIZED_DISPLAY_NAME:-my-workstation}"

usage() {
  cat <<EOF
Usage: $0 [--var-file PATH]

Options:
  --var-file PATH  Terraform variable file relative to terraform/ (default: $VAR_FILE)
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --var-file" >&2; exit 2; }
      VAR_FILE="$2"
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

[[ -n "$MASTER_AUTHORIZED_IP" ]] || {
  echo "Set MASTER_AUTHORIZED_IP to a trusted control-plane CIDR before running this script." >&2
  exit 1
}
[[ "$MASTER_AUTHORIZED_IP" != "0.0.0.0/0" ]] || {
  echo "MASTER_AUTHORIZED_IP must not be 0.0.0.0/0." >&2
  exit 1
}
MASTER_AUTHORIZED_NETWORKS_VAR="master_authorized_networks=[{\"cidr_block\":\"$MASTER_AUTHORIZED_IP\",\"display_name\":\"$MASTER_AUTHORIZED_DISPLAY_NAME\"}]"

cd "$REPOSITORY_ROOT"

echo "Formatting Terraform..."
terraform -chdir="$TERRAFORM_DIR" fmt -check -recursive

echo "Initializing Terraform..."
terraform -chdir="$TERRAFORM_DIR" init -input=false

echo "Validating Terraform..."
terraform -chdir="$TERRAFORM_DIR" validate

echo "Creating Terraform plan..."
terraform -chdir="$TERRAFORM_DIR" plan -input=false -var-file="$VAR_FILE" -var="$MASTER_AUTHORIZED_NETWORKS_VAR"
