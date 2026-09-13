# Deployment

This project deploys the application to Google Cloud using Terraform and GKE. Bootstrap resources are created separately from application infrastructure and must remain available during application rebuilds.

## Prerequisites

You need:

- A Google Cloud project with billing enabled.
- `gcloud`, Terraform 1.6+, Docker, `kubectl`, and the GKE authentication plugin.
- A trusted CIDR for GKE control-plane access. Never use `0.0.0.0/0`.
- A GitHub repository in `OWNER/REPOSITORY` form.

The example configuration is in `terraform/environments/dev.tfvars`. Replace environment-specific values before applying it.

## Bootstrap State and Identity

The remote backend uses `gs://nolan-sre-challenge-tfstate` with the prefix `terraform/state`.

First create the bucket. This helper is safe to rerun and does not initialize Terraform state or delete resources:

```bash
./scripts/bootstrap-state-bucket.sh --project-id YOUR_PROJECT_ID
```

Authenticate with an administrator account, then create the state-bootstrap resources:

```bash
terraform -chdir=terraform/state-bootstrap init
terraform -chdir=terraform/state-bootstrap apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="github_repository=OWNER/REPOSITORY" \
  -var='terraform_state_members=["user:YOUR_ACCOUNT","serviceAccount:github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com"]'
```

Initialize the main configuration and migrate any existing local state:

```bash
terraform -chdir=terraform init -migrate-state
```

State bootstrap creates the protected, versioned bucket, GitHub Workload Identity Federation, and GitHub service accounts. These resources are intentionally separate from the application Terraform state.

## Provision Infrastructure

Set a trusted control-plane CIDR and use the repository script to format, initialize, validate, and plan the application infrastructure:

```bash
export MASTER_AUTHORIZED_IP=YOUR_TRUSTED_CIDR
./scripts/plan.sh
```

Review the plan, then apply it with the deployment script:

```bash
./scripts/deploy.sh
```

The deployment script applies Terraform, builds and pushes the application image, applies the Kubernetes manifest, and waits for the rollout. Use `scripts/plan.sh` when you only need to inspect infrastructure changes.

The infrastructure creates the VPC, private Autopilot GKE cluster, Artifact Registry repository, Workload Identity bindings, load-balancer monitoring, SLO, dashboard, and alerts.

## Deploy an Existing Application Image

To deploy an already-published image, use an immutable digest. This skips Terraform and image building:

```bash
./scripts/deploy.sh \
  --image-reference REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE@sha256:DIGEST
```

Verify the workload and ingress:

```bash
gcloud container clusters get-credentials nolan-sre --region us-central1 --project YOUR_PROJECT_ID
kubectl --namespace nolan-sre get pods,service,ingress
kubectl --namespace nolan-sre rollout status deployment/nolan-sre --timeout=5m
```

## Rollback

Roll back by deploying a previously verified digest, then check rollout status and history:

```bash
./scripts/deploy.sh --image-reference REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE@sha256:KNOWN_GOOD_DIGEST
kubectl --namespace nolan-sre rollout status deployment/nolan-sre --timeout=5m
kubectl --namespace nolan-sre rollout history deployment/nolan-sre
```

## Teardown

Application teardown must not remove the remote state bucket, Workload Identity pool, or GitHub identities. The protected GitHub workflow `destroy-application.yaml` uses the `terraform-destroy` environment and destroys application Terraform resources only.

For local teardown, use the confirmation-protected script:

```bash
export MASTER_AUTHORIZED_IP=YOUR_TRUSTED_CIDR
./scripts/teardown.sh
```

The script requires typing `DESTROY` unless `--force` is supplied. Do not run teardown against shared or production infrastructure without reviewing the plan and state boundary first.
