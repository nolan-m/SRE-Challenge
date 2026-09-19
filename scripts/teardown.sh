#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
VAR_FILE="environments/dev.tfvars"
CLUSTER_NAME="nolan-sre"
NAMESPACE="nolan-sre"
SKIP_KUBERNETES=false
FORCE=false
MASTER_AUTHORIZED_IP="${MASTER_AUTHORIZED_IP:-}"
MASTER_AUTHORIZED_DISPLAY_NAME="${MASTER_AUTHORIZED_DISPLAY_NAME:-my-workstation}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --var-file PATH       Terraform variable file relative to terraform/ (default: $VAR_FILE)
  --skip-kubernetes     Skip namespace deletion before Terraform destroy
  --force               Skip the DESTROY confirmation prompt
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || { echo "Missing value for --var-file" >&2; exit 2; }
      VAR_FILE="$2"
      shift 2
      ;;
    --skip-kubernetes)
      SKIP_KUBERNETES=true
      shift
      ;;
    --force)
      FORCE=true
      shift
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

TFVARS_PATH="$TERRAFORM_DIR/$VAR_FILE"
[[ -f "$TFVARS_PATH" ]] || { echo "Terraform variable file not found: $TFVARS_PATH" >&2; exit 1; }
read_tfvar() {
  local name="$1"
  sed -nE "s/^[[:space:]]*$name[[:space:]]*=[[:space:]]*\"([^\"]+)\".*\$/\1/p" "$TFVARS_PATH" | head -n 1
}
PROJECT_ID="$(read_tfvar project_id)"
REGION="$(read_tfvar region)"
SECONDARY_REGION="$(read_tfvar secondary_region)"
SECONDARY_CLUSTER_NAME="$(read_tfvar secondary_cluster_name)"
[[ -n "$PROJECT_ID" && -n "$REGION" && -n "$SECONDARY_REGION" && -n "$SECONDARY_CLUSTER_NAME" ]] || { echo "The selected tfvars file must define project_id, region, secondary_region, and secondary_cluster_name." >&2; exit 1; }
[[ -n "$MASTER_AUTHORIZED_IP" ]] || {
  echo "Set MASTER_AUTHORIZED_IP to a trusted control-plane CIDR before running this script." >&2
  exit 1
}
[[ "$MASTER_AUTHORIZED_IP" != "0.0.0.0/0" ]] || {
  echo "MASTER_AUTHORIZED_IP must not be 0.0.0.0/0." >&2
  exit 1
}
MASTER_AUTHORIZED_NETWORKS_VAR="master_authorized_networks=[{\"cidr_block\":\"$MASTER_AUTHORIZED_IP\",\"display_name\":\"$MASTER_AUTHORIZED_DISPLAY_NAME\"}]"

if [[ "$FORCE" != true ]]; then
  read -r -p "This will delete the nolan-sre workload and Terraform infrastructure. Type DESTROY to continue: " confirmation
  [[ "$confirmation" == "DESTROY" ]] || { echo "Teardown cancelled."; exit 0; }
fi

cd "$REPOSITORY_ROOT"
if [[ "$SKIP_KUBERNETES" != true ]]; then
  for cluster_region in "$CLUSTER_NAME:$REGION" "$SECONDARY_CLUSTER_NAME:$SECONDARY_REGION"; do
    cluster="${cluster_region%%:*}"
    region="${cluster_region##*:}"
    echo "Fetching credentials for $cluster ($region)..."
    if gcloud container clusters get-credentials "$cluster" --region "$region" --project "$PROJECT_ID"; then
      echo "Deleting Kubernetes namespace..."
      kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --wait=true
    else
      echo "Unable to fetch credentials for $cluster; continuing." >&2
    fi
  done
fi

echo "Destroying Terraform infrastructure..."
terraform -chdir="$TERRAFORM_DIR" destroy -input=false -auto-approve -var-file="$VAR_FILE" -var="$MASTER_AUTHORIZED_NETWORKS_VAR"
echo "Teardown completed."
