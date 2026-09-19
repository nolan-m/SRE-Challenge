#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
VAR_FILE="environments/dev.tfvars"
NAMESPACE="nolan-sre"

usage() {
  cat <<EOF
Usage: $0 [options]

Reports cluster, workload, and load-balancer health across both regions:
GKE cluster status, Pod/Deployment/HPA state on each cluster, global
backend-service health per zone, and a live HTTP check against the load
balancer IP. Read-only; makes no changes.

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

TFVARS_PATH="$TERRAFORM_DIR/$VAR_FILE"
[[ -f "$TFVARS_PATH" ]] || { echo "Terraform variable file not found: $TFVARS_PATH" >&2; exit 1; }

read_tfvar() {
  local name="$1"
  sed -nE "s/^[[:space:]]*$name[[:space:]]*=[[:space:]]*\"([^\"]+)\".*$/\1/p" "$TFVARS_PATH" | head -n 1
}

PROJECT_ID="$(read_tfvar project_id)"
PRIMARY_REGION="$(read_tfvar region)"
PRIMARY_CLUSTER_NAME="$(read_tfvar cluster_name)"
SECONDARY_REGION="$(read_tfvar secondary_region)"
SECONDARY_CLUSTER_NAME="$(read_tfvar secondary_cluster_name)"
[[ -n "$PROJECT_ID" && -n "$PRIMARY_REGION" && -n "$PRIMARY_CLUSTER_NAME" && -n "$SECONDARY_REGION" && -n "$SECONDARY_CLUSTER_NAME" ]] || {
  echo "The selected tfvars file must define project_id, region, cluster_name, secondary_region, and secondary_cluster_name." >&2
  exit 1
}
BACKEND_SERVICE="${PRIMARY_CLUSTER_NAME}-backend"

echo "=== GKE clusters ==="
gcloud container clusters list --project "$PROJECT_ID" \
  --filter="name:(${PRIMARY_CLUSTER_NAME} ${SECONDARY_CLUSTER_NAME})" \
  --format="table(name,location,status,currentNodeCount)"

for pair in "${PRIMARY_CLUSTER_NAME}:${PRIMARY_REGION}" "${SECONDARY_CLUSTER_NAME}:${SECONDARY_REGION}"; do
  cluster="${pair%%:*}"
  region="${pair##*:}"
  echo
  echo "=== $cluster ($region) workload ==="
  gcloud container clusters get-credentials "$cluster" --region "$region" --project "$PROJECT_ID" >/dev/null 2>&1
  kubectl --namespace "$NAMESPACE" get pods,deployment,hpa 2>&1
done

echo
echo "=== Global load balancer backend health ($BACKEND_SERVICE) ==="
gcloud compute backend-services get-health "$BACKEND_SERVICE" --global --project "$PROJECT_ID" \
  --format="table(status.healthStatus[].ipAddress,status.healthStatus[].healthState)" 2>&1 || {
  echo "Unable to read backend-service health; check the name and enable_load_balancer_backends." >&2
}

echo
echo "=== Live HTTP check ==="
LOAD_BALANCER_IP="$(terraform -chdir="$TERRAFORM_DIR" output -raw load_balancer_ip 2>/dev/null || true)"
if [[ -n "$LOAD_BALANCER_IP" ]]; then
  echo "Load balancer IP: $LOAD_BALANCER_IP"
  if curl --fail --silent --show-error --max-time 10 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" "http://$LOAD_BALANCER_IP/"; then
    :
  else
    echo "Request to http://$LOAD_BALANCER_IP/ failed." >&2
  fi
else
  echo "load_balancer_ip output not available; run terraform apply first." >&2
fi
