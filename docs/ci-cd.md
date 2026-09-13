# CI/CD

GitHub Actions uses short-lived Google Cloud credentials through GitHub OIDC and Workload Identity Federation. No service-account JSON key is stored in GitHub.

## Workflow Boundaries

| Workflow | Trigger and scope | Purpose |
| --- | --- | --- |
| `on-pr.yaml` | Every pull request | Terraform formatting and validation, Kubernetes placeholder checks, container build, and HTTP smoke test. |
| `on-release.yaml` | Pushes to `main` or creation of a `v*` version tag | Runs `release-please` on `main`; deploys only after a release tag is created by the merged release PR. |
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
| `TF_VAR_NOTIFICATION_EMAILS` | `["YOUR_SUPPORT_EMAIL"]` |

Replace `PROJECT_NUMBER` with the numeric project number found in the GCP Console. Replace the example CIDR with the trusted network allowed to reach the GKE control plane; never use `0.0.0.0/0`.

## Pull Request Validation

The PR workflow checks Terraform formatting and validation, verifies that the Kubernetes manifest still contains exactly one image placeholder and no TODO/FIXME markers, builds the container, and runs it on port 18080 for an HTTP smoke test.

## Release and Deployment

The release flow has two separate stages:

1. A push to `main` runs `release-please`. It creates or updates a release PR when Conventional Commits contain releasable changes. No application deployment occurs from this branch push.
2. After the release PR is merged, `release-please` creates a `v*` version tag. That tag starts the deployment path, which checks out the tagged commit and deploys it.

Conventional Commits determine release versions:

- `fix:` creates a patch release.
- `feat:` creates a minor release.
- A breaking change creates a major release.

The tag deployment job runs on a self-hosted runner with labels `self-hosted`, `linux`, `x64`, and `gcp`. It authenticates with OIDC, logs in to Artifact Registry, publishes a SHA tag and the release tag, and captures the registry digest.

Kubernetes is rendered with `IMAGE_REPOSITORY@sha256:DIGEST`. Mutable tags are never used as the deployment reference. The job applies the rendered manifest and waits for `deployment/nolan-sre` to complete its rollout.

A Kubernetes-only change on `main` can create a release PR according to `release-please`; deployment occurs only after that PR is merged and its version tag is pushed.

The workflow uses the built-in `GITHUB_TOKEN` for `release-please`. GitHub may suppress a follow-on workflow for a tag created by `GITHUB_TOKEN`; if the tag appears but deployment does not start, a dedicated GitHub App or fine-grained token may be required.

## Infrastructure Changes

The Terraform workflow initializes, formats, validates, and plans with `terraform/environments/dev.tfvars`. Changes merged to `main` automatically apply the reviewed plan through the protected `terraform-apply` environment. Manual dispatch also creates a plan, but applies it only when the `apply` input is enabled; the input has no effect on push-triggered runs.

## Runner Requirements

The GKE deployment runner requires Docker, `gcloud`, `kubectl`, the GKE authentication plugin, outbound NAT access to GitHub and Google APIs, and network access to the GKE control plane. Its control-plane access must be limited by trusted master authorized networks.

## Access Controls

The bootstrap Terraform restricts the OIDC provider to the configured repository and branch. GitHub receives short-lived credentials only through Workload Identity Federation. Configure `terraform-apply` and `terraform-destroy` as protected environments with appropriate reviewers before using the corresponding workflows.
