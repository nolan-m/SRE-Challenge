#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
VAR_FILE="environments/dev.tfvars"
NAMESPACE="nolan-sre"
TARGET="primary"
RESTORE=true
FORCE=false
POLL_INTERVAL=5
# Autopilot scales nodes to zero when replicas hit 0, so restoring can require new node
# provisioning (often 1-3+ minutes) on top of Pod scheduling, NEG registration, and LB
# health-check convergence; default timeout is generous to accommodate that.
POLL_TIMEOUT=420

usage() {
  cat <<EOF
Usage: $0 [options]

Simulates a regional failure by scaling the target cluster's Deployment to zero
replicas, then (by default) restores it once the backend service reports unhealthy.
Never modifies Terraform state, master-authorized-networks, or DNS.

Options:
  --var-file PATH       Terraform variable file relative to terraform/ (default: $VAR_FILE)
  --target REGION       Which region to fail: primary or secondary (default: $TARGET)
  --no-restore          Leave the target scaled to zero after the drain is confirmed
  --poll-timeout SECONDS  Max seconds to wait for each health-state transition (default: $POLL_TIMEOUT)
  --force               Skip the confirmation prompt
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
    --target)
      [[ $# -ge 2 ]] || { echo "Missing value for --target" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --no-restore)
      RESTORE=false
      shift
      ;;
    --poll-timeout)
      [[ $# -ge 2 ]] || { echo "Missing value for --poll-timeout" >&2; exit 2; }
      POLL_TIMEOUT="$2"
      shift 2
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

[[ "$TARGET" == "primary" || "$TARGET" == "secondary" ]] || {
  echo "--target must be 'primary' or 'secondary'." >&2
  exit 2
}

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

if [[ "$TARGET" == "primary" ]]; then
  TARGET_CLUSTER="$PRIMARY_CLUSTER_NAME"
  TARGET_REGION="$PRIMARY_REGION"
else
  TARGET_CLUSTER="$SECONDARY_CLUSTER_NAME"
  TARGET_REGION="$SECONDARY_REGION"
fi

BACKEND_SERVICE="${PRIMARY_CLUSTER_NAME}-backend"
GLOBAL_IP="$(terraform -chdir="$TERRAFORM_DIR" output -raw load_balancer_ip 2>/dev/null || true)"

if [[ "$FORCE" != true ]]; then
  read -r -p "This will scale deployment/nolan-sre to 0 replicas on the $TARGET cluster ($TARGET_CLUSTER, $TARGET_REGION). Type FAILOVER to continue: " confirmation
  [[ "$confirmation" == "FAILOVER" ]] || { echo "Failover simulation cancelled."; exit 0; }
fi

echo "Fetching credentials for $TARGET_CLUSTER ($TARGET_REGION)..."
gcloud container clusters get-credentials "$TARGET_CLUSTER" --region "$TARGET_REGION" --project "$PROJECT_ID"

ORIGINAL_REPLICAS="$(kubectl --namespace "$NAMESPACE" get deployment nolan-sre --output=jsonpath='{.spec.replicas}')"
echo "Current replica count on $TARGET: $ORIGINAL_REPLICAS"

echo "Draining $TARGET by scaling deployment/nolan-sre to 0 replicas..."
START_TIME="$(date +%s)"
kubectl --namespace "$NAMESPACE" scale deployment/nolan-sre --replicas=0

echo "Waiting for the backend service to report the $TARGET region UNHEALTHY..."
while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  if [[ -n "$BACKEND_SERVICE" ]] && gcloud compute backend-services get-health "$BACKEND_SERVICE" --global --project "$PROJECT_ID" --format='value(status.healthStatus[].healthState)' 2>/dev/null | grep -q "UNHEALTHY"; then
    echo "Detected UNHEALTHY backend(s) after ${ELAPSED}s (approximate RTO)."
    break
  fi
  if (( ELAPSED >= POLL_TIMEOUT )); then
    echo "Timed out after ${POLL_TIMEOUT}s waiting for an UNHEALTHY backend; current health:" >&2
    gcloud compute backend-services get-health "$BACKEND_SERVICE" --global --project "$PROJECT_ID" 2>&1 >&2 || true
    break
  fi
  sleep "$POLL_INTERVAL"
done

if [[ -n "$GLOBAL_IP" ]]; then
  echo "Confirm traffic is still served (from the healthy region): curl http://$GLOBAL_IP/"
fi

if [[ "$RESTORE" != true ]]; then
  echo "Leaving $TARGET scaled to 0 replicas (--no-restore). Restore manually with:"
  echo "  kubectl --namespace $NAMESPACE scale deployment/nolan-sre --replicas=$ORIGINAL_REPLICAS"
  exit 0
fi

echo "Restoring $TARGET to $ORIGINAL_REPLICAS replicas..."
RESTORE_START="$(date +%s)"
kubectl --namespace "$NAMESPACE" scale deployment/nolan-sre --replicas="$ORIGINAL_REPLICAS"
kubectl --namespace "$NAMESPACE" rollout status deployment/nolan-sre --timeout=5m

echo "Waiting for the backend service to report the $TARGET region HEALTHY again..."
while true; do
  ELAPSED=$(( $(date +%s) - RESTORE_START ))
  if [[ -n "$BACKEND_SERVICE" ]] && ! gcloud compute backend-services get-health "$BACKEND_SERVICE" --global --project "$PROJECT_ID" --format='value(status.healthStatus[].healthState)' 2>/dev/null | grep -q "UNHEALTHY"; then
    echo "Backends report HEALTHY after ${ELAPSED}s (approximate failback time)."
    break
  fi
  if (( ELAPSED >= POLL_TIMEOUT )); then
    echo "Timed out after ${POLL_TIMEOUT}s waiting for HEALTHY backends; current health:" >&2
    gcloud compute backend-services get-health "$BACKEND_SERVICE" --global --project "$PROJECT_ID" 2>&1 >&2 || true
    echo "Autopilot may still be provisioning nodes for the restored replicas; check 'kubectl -n $NAMESPACE get pods,nodes' and re-run 'gcloud compute backend-services get-health' shortly." >&2
    break
  fi
  sleep "$POLL_INTERVAL"
done

echo "Failover simulation completed."
