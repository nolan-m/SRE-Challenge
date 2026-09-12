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
ARTIFACT_REGISTRY_REPOSITORY="$(read_tfvar artifact_registry_repository)"
NAMESPACE="$CLUSTER_NAME"
[[ -n "$PROJECT_ID" && -n "$REGION" && -n "$CLUSTER_NAME" && -n "$ARTIFACT_REGISTRY_REPOSITORY" ]] || {
  echo "The selected tfvars file must define project_id, region, cluster_name, and artifact_registry_repository." >&2
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

echo "Initializing Terraform..."
terraform -chdir="$TERRAFORM_DIR" init -input=false

echo "Validating Terraform..."
terraform -chdir="$TERRAFORM_DIR" validate

echo "Applying Terraform..."
terraform -chdir="$TERRAFORM_DIR" apply -input=false -auto-approve -var-file="$VAR_FILE" -var="$MASTER_AUTHORIZED_NETWORKS_VAR"

echo "Configuring Docker authentication..."
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

IMAGE_REPOSITORY="$REGION-docker.pkg.dev/$PROJECT_ID/$ARTIFACT_REGISTRY_REPOSITORY/$ARTIFACT_REGISTRY_REPOSITORY"
IMAGE="$IMAGE_REPOSITORY:$IMAGE_TAG"
echo "Building image $IMAGE..."
docker build --tag "$IMAGE" "$REPOSITORY_ROOT"
echo "Pushing image $IMAGE..."
docker push "$IMAGE"

sed -e "s|REGION-docker.pkg.dev/PROJECT_ID/nolan-sre/nolan-sre:IMAGE_DIGEST|$IMAGE|g" \
    "$MANIFEST_PATH" > "$RENDERED_MANIFEST_PATH"
if grep -qE 'REGION-docker.pkg.dev|PROJECT_ID' "$RENDERED_MANIFEST_PATH"; then
  echo "Rendered manifest still contains an unresolved placeholder." >&2
  exit 1
fi

echo "Configuring GKE credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"
echo "Applying Kubernetes resources..."
kubectl apply --filename "$RENDERED_MANIFEST_PATH"
echo "Waiting for rollout..."
kubectl --namespace "$NAMESPACE" rollout status "deployment/$CLUSTER_NAME" --timeout=5m

INGRESS_IP="$(kubectl --namespace "$NAMESPACE" get ingress "$CLUSTER_NAME" --output=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
echo "Deployment completed."
echo "Image: $IMAGE"
if [[ -n "$INGRESS_IP" ]]; then
  echo "GKE Ingress external IP: $INGRESS_IP"
else
  echo "GKE is still provisioning the Ingress external IP. Check with: kubectl --namespace $NAMESPACE get ingress $CLUSTER_NAME"
fi
