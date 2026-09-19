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

The deployment script applies Terraform, builds and pushes the application image, applies the Kubernetes manifest to both the primary and secondary clusters, and waits for the rollout on each. Use `scripts/plan.sh` when you only need to inspect infrastructure changes.

The infrastructure creates the VPC with regional subnets in both regions, two private Autopilot GKE clusters (primary and secondary), Cloud Router/NAT per region, Artifact Registry repository, Workload Identity bindings, a global external HTTP load balancer with standalone-NEG backends across both regions, load-balancer monitoring, SLO, dashboard, and alerts.

Standalone NEGs are created by GKE only after the annotated Service has ready Pods, so wiring them into the load balancer is a two-step process controlled by `enable_load_balancer_backends` in `terraform/environments/dev.tfvars` (default `false`):

1. With `enable_load_balancer_backends = false`, apply Terraform and run `./scripts/deploy.sh`. This creates the clusters, network, and the load balancer's IP/health check/proxy/forwarding rule (with no backends yet), and deploys the app to both clusters, which creates the `nolan-sre-neg` NEG in each zone.
2. Confirm the NEGs exist: `gcloud compute network-endpoint-groups list --filter="name=nolan-sre-neg"` should list an entry per zone in both regions.
3. Set `enable_load_balancer_backends = true` in the tfvars file and re-apply (`./scripts/plan.sh` then `./scripts/deploy.sh`, or `terraform apply`) to attach the NEGs as backends.

Running `terraform plan`/`apply` with `enable_load_balancer_backends = true` before the NEGs exist reproduces a `networkEndpointGroups ... not found` error; set it back to `false` (or deploy the app first) to unblock the plan.

## Deploy an Existing Application Image

To deploy an already-published image, use an immutable digest. This skips Terraform and image building:

```bash
./scripts/deploy.sh \
  --image-reference REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE@sha256:DIGEST
```

Verify the workload on each cluster:

```bash
gcloud container clusters get-credentials nolan-sre --region us-central1 --project YOUR_PROJECT_ID
kubectl --namespace nolan-sre get pods,service

gcloud container clusters get-credentials nolan-sre-secondary --region us-east1 --project YOUR_PROJECT_ID
kubectl --namespace nolan-sre get pods,service
```

Check the shared load balancer:

```bash
terraform -chdir=terraform output -raw load_balancer_ip
curl --fail http://LOAD_BALANCER_IP/
```

Or run `./scripts/check-health.sh` for a combined read-only summary of both clusters' workloads, backend-service health, and a live load-balancer check.

## Rollback

Roll back by deploying a previously verified digest, then check rollout status and history:

```bash
./scripts/deploy.sh --image-reference REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE@sha256:KNOWN_GOOD_DIGEST
kubectl --namespace nolan-sre rollout status deployment/nolan-sre --timeout=5m
kubectl --namespace nolan-sre rollout history deployment/nolan-sre
```

## Simulate a Regional Failover

To verify cross-region failover without touching Terraform state or DNS:

```bash
./scripts/simulate-failover.sh --target primary
```

The script drains one region's replicas, confirms the load balancer marks it `UNHEALTHY`, then restores it and confirms recovery. See [Runbook](runbook.md) for details.

## Teardown

Application teardown must not remove the remote state bucket, Workload Identity pool, or GitHub identities. The protected GitHub workflow `destroy-application.yaml` uses the `terraform-destroy` environment and destroys application Terraform resources only.

For local teardown, use the confirmation-protected script:

```bash
export MASTER_AUTHORIZED_IP=YOUR_TRUSTED_CIDR
./scripts/teardown.sh
```

The script requires typing `DESTROY` unless `--force` is supplied. Do not run teardown against shared or production infrastructure without reviewing the plan and state boundary first.
