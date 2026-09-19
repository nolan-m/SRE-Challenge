#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPOSITORY_ROOT/terraform"
MANIFEST_PATH="$REPOSITORY_ROOT/kubernetes/manifest.yaml"
RENDERED_MANIFEST_PATH="$REPOSITORY_ROOT/kubernetes/static-site.rendered.yaml"
VAR_FILE="environments/dev.tfvars"
PROJECT_ID=""
REGION=""
CLUSTER_NAME=""
ARTIFACT_REGISTRY_REPOSITORY=""
IMAGE_TAG=""
IMAGE_REFERENCE=""
MASTER_AUTHORIZED_IP="${MASTER_AUTHORIZED_IP:-}"
MASTER_AUTHORIZED_DISPLAY_NAME="${MASTER_AUTHORIZED_DISPLAY_NAME:-my-workstation}"

cleanup() {
  rm -f "$RENDERED_MANIFEST_PATH"
}
trap cleanup EXIT

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --var-file PATH       Terraform variable file relative to terraform/ (default: $VAR_FILE)
  --image-tag TAG       Container tag (default: current Git commit)
  --image-reference REF Deploy an existing image reference instead of building and pushing
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
    --image-tag)
      [[ $# -ge 2 ]] || { echo "Missing value for --image-tag" >&2; exit 2; }
      IMAGE_TAG="$2"
      shift 2
      ;;
    --image-reference)
      [[ $# -ge 2 ]] || { echo "Missing value for --image-reference" >&2; exit 2; }
      IMAGE_REFERENCE="$2"
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
REGION="$(read_tfvar region)"
CLUSTER_NAME="$(read_tfvar cluster_name)"
SECONDARY_REGION="$(read_tfvar secondary_region)"
SECONDARY_CLUSTER_NAME="$(read_tfvar secondary_cluster_name)"
ARTIFACT_REGISTRY_REPOSITORY="$(read_tfvar artifact_registry_repository)"
NAMESPACE="nolan-sre"
[[ -n "$PROJECT_ID" && -n "$REGION" && -n "$CLUSTER_NAME" && -n "$SECONDARY_REGION" && -n "$SECONDARY_CLUSTER_NAME" && -n "$ARTIFACT_REGISTRY_REPOSITORY" ]] || {
  echo "The selected tfvars file must define project_id, region, cluster_name, secondary_region, secondary_cluster_name, and artifact_registry_repository." >&2
  exit 1
}
[[ "$PROJECT_ID" != replace-with-your-gcp-project-id ]] || {
  echo "Replace the project_id placeholder in $TFVARS_PATH before deploying." >&2
  exit 1
}
[[ -n "$MASTER_AUTHORIZED_IP" ]] || {
  echo "Set MASTER_AUTHORIZED_IP to a trusted control-plane CIDR before running this script." >&2
  exit 1
}
[[ "$MASTER_AUTHORIZED_IP" != "0.0.0.0/0" ]] || {
  echo "MASTER_AUTHORIZED_IP must not be 0.0.0.0/0." >&2
  exit 1
}
MASTER_AUTHORIZED_NETWORKS_VAR="master_authorized_networks=[{\"cidr_block\":\"$MASTER_AUTHORIZED_IP\",\"display_name\":\"$MASTER_AUTHORIZED_DISPLAY_NAME\"}]"

if [[ -z "$IMAGE_TAG" ]]; then
  IMAGE_TAG="$(git -C "$REPOSITORY_ROOT" rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"
fi
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "Image tag contains unsupported characters: $IMAGE_TAG" >&2
  exit 2
}

cd "$REPOSITORY_ROOT"

IMAGE_REPOSITORY="$REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REGISTRY_REPOSITORY/$ARTIFACT_REGISTRY_REPOSITORY"
if [[ -n "$IMAGE_REFERENCE" ]]; then
  [[ "$IMAGE_REFERENCE" =~ @sha256:[a-f0-9]{64}$ ]] || {
    echo "--image-reference must use an immutable sha256 digest reference." >&2
    exit 2
  }
  IMAGE="$IMAGE_REFERENCE"
else
  echo "Initializing Terraform..."
  terraform -chdir="$TERRAFORM_DIR" init -input=false

  echo "Validating Terraform..."
  terraform -chdir="$TERRAFORM_DIR" validate

  echo "Applying Terraform..."
  terraform -chdir="$TERRAFORM_DIR" apply -input=false -auto-approve -var-file="$VAR_FILE" -var="$MASTER_AUTHORIZED_NETWORKS_VAR"

  echo "Configuring Docker authentication..."
  gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

  IMAGE="$IMAGE_REPOSITORY:$IMAGE_TAG"
  echo "Building image $IMAGE..."
  docker build --tag "$IMAGE" "$REPOSITORY_ROOT"
  echo "Pushing image $IMAGE..."
  docker push "$IMAGE"
fi

sed -e "s|REGION-docker.pkg.dev/PROJECT_ID/nolan-sre/nolan-sre:IMAGE_DIGEST|$IMAGE|g" \
    "$MANIFEST_PATH" > "$RENDERED_MANIFEST_PATH"
if grep -qE 'REGION-docker.pkg.dev|PROJECT_ID' "$RENDERED_MANIFEST_PATH"; then
  echo "Rendered manifest still contains an unresolved placeholder." >&2
  exit 1
fi

echo "Configuring GKE credentials and applying to both regions..."
for cluster_region in "$CLUSTER_NAME:$REGION" "$SECONDARY_CLUSTER_NAME:$SECONDARY_REGION"; do
  cluster="${cluster_region%%:*}"
  region="${cluster_region##*:}"
  echo "--- $cluster ($region) ---"
  gcloud container clusters get-credentials "$cluster" --region "$region" --project "$PROJECT_ID"
  kubectl apply --filename "$RENDERED_MANIFEST_PATH"
  echo "Waiting for rollout..."
  kubectl --namespace "$NAMESPACE" rollout status "deployment/nolan-sre" --timeout=5m
done

LOAD_BALANCER_IP="$(terraform -chdir="$TERRAFORM_DIR" output -raw load_balancer_ip 2>/dev/null || true)"
echo "Deployment completed."
echo "Image: $IMAGE"
if [[ -n "$LOAD_BALANCER_IP" ]]; then
  echo "Global load balancer IP: http://$LOAD_BALANCER_IP/"
else
  echo "Load balancer IP not available yet. Apply terraform/load_balancer.tf after confirming NEGs exist in both regions, then check: terraform -chdir=$TERRAFORM_DIR output load_balancer_ip"
fi
