# CI/CD

GitHub Actions uses short-lived Google Cloud credentials through GitHub OIDC and Workload Identity Federation. No service-account JSON key is stored in GitHub.

## Workflow Boundaries

| Workflow | Trigger and scope | Purpose |
| --- | --- | --- |
| `on-pr.yaml` | Every pull request | Terraform formatting and validation, Kubernetes placeholder checks, container build, and HTTP smoke test. |
| `on-release.yaml` | Pushes to `main` affecting `app/**`, `Dockerfile`, `kubernetes/**`, or release metadata | Creates or updates the release PR, builds the image, publishes it, and deploys the digest. |
| `on-infrastructure-update.yaml` | Pushes to `main` affecting `terraform/**`; also manual dispatch | Plans Terraform and automatically applies push-triggered plans. Manual runs apply only when the `apply` input is enabled. |
| `on-state-bootstrap.yaml` | State-bootstrap or bootstrap-script changes; also manual dispatch | Runs the state-bootstrap helper workflow. Bootstrap remains an administrative lifecycle. |
| `destroy-application.yaml` | Manual dispatch | Destroys application infrastructure through the protected `terraform-destroy` environment. It does not target bootstrap state. |

Changes under `kubernetes/**` belong to `on-release.yaml`, not the Terraform workflow.

## GitHub Actions Repository Variables

Configure these repository variables:

| Variable | Example value |
| --- | --- |
| `GCP_PROJECT_ID` | `nolan-sre-challenge` |
| `GCP_REGION` | `us-central1` |
| `PROJECT_NAMESPACE` | `nolan-sre` |
| `GCP_WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github-oidc` |
| `GCP_DEPLOYER_SERVICE_ACCOUNT` | `github-actions-deployer@nolan-sre-challenge.iam.gserviceaccount.com` |
| `TF_VAR_MASTER_AUTHORIZED_NETWORKS` | `[{"cidr_block":"203.0.113.10/32","display_name":"my-laptop"}]` |

Replace `PROJECT_NUMBER` with the numeric project number found in the GCP Console. Replace the example CIDR with the trusted network allowed to reach the GKE control plane; never use `0.0.0.0/0`.


## Pull Request Validation

The PR workflow checks Terraform formatting and validation, verifies that the Kubernetes manifest still contains exactly one image placeholder and no TODO/FIXME markers, builds the container, and runs it on port 18080 for an HTTP smoke test.

## Release and Deployment

`on-release.yaml` runs `release-please` on `main`. Conventional Commits determine release versions:

- `fix:` creates a patch release.
- `feat:` creates a minor release.
- A breaking change creates a major release.

The deployment job runs on a self-hosted runner with labels `self-hosted`, `linux`, `x64`, and `gcp`. It authenticates with OIDC, logs in to Artifact Registry, publishes a SHA tag and an optional release tag, and captures the registry digest.

Kubernetes is rendered with `IMAGE_REPOSITORY@sha256:DIGEST`. Mutable tags are never used as the deployment reference. The job applies the rendered manifest and waits for `deployment/nolan-sre` to complete its rollout.

A Kubernetes-only change still builds and deploys a new immutable image. It creates a release only when the commit is releasable according to `release-please`.

## Infrastructure Changes

The Terraform workflow initializes, formats, validates, and plans with `terraform/environments/dev.tfvars`. Changes merged to `main` automatically apply the reviewed plan through the protected `terraform-apply` environment. Manual dispatch also creates a plan, but applies it only when the `apply` input is enabled; the input has no effect on push-triggered runs.

After applying the infrastructure, retrieve the values used by GitHub Actions:

```bash
terraform -chdir=terraform output github_actions_workload_identity_provider
terraform -chdir=terraform output github_actions_deployer_service_account
terraform -chdir=terraform output github_actions_image_repository
```

The workflow also passes the repository name as `TF_VAR_github_repository`.

## Runner Requirements

The GKE deployment runner requires Docker, `gcloud`, `kubectl`, the GKE authentication plugin, outbound NAT access to GitHub and Google APIs, and network access to the GKE control plane. Its control-plane access must be limited by trusted master authorized networks.

## Access Controls

The bootstrap Terraform restricts the OIDC provider to the configured repository and branch. GitHub receives short-lived credentials only through Workload Identity Federation. Configure `terraform-apply` and `terraform-destroy` as protected environments with appropriate reviewers before using the corresponding workflows.
