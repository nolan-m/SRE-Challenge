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

Replace `PROJECT_NUMBER` with the numeric project number found in the GCP Console. Set `GCP_REGION` to `us-central1`; `central1` is not a valid region. Replace the example CIDR with the trusted network allowed to reach the GKE control plane; never use `0.0.0.0/0`.

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

The tag deployment job runs on the GitHub-hosted `ubuntu-latest` runner. It authenticates with OIDC, logs in to Artifact Registry, publishes a SHA tag and the release tag, and captures the registry digest.

Kubernetes is rendered with `IMAGE_REPOSITORY@sha256:DIGEST`. Mutable tags are never used as the deployment reference. The job applies the rendered manifest and waits for `deployment/nolan-sre` to complete its rollout.

A Kubernetes-only change on `main` can create a release PR according to `release-please`; deployment occurs only after that PR is merged and its version tag is pushed.

The release job uses the `RELEASE_PLEASE_TOKEN` repository secret rather than the built-in `GITHUB_TOKEN`. This is required because GitHub suppresses follow-on workflow runs for tags created by `GITHUB_TOKEN`. Configure `RELEASE_PLEASE_TOKEN` with a GitHub App or fine-grained personal access token that can read repository metadata, write contents, and write pull requests.

### Create `RELEASE_PLEASE_TOKEN`

Create a fine-grained GitHub personal access token:

1. Open **GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens**.
2. Select **Generate new token**.
3. Set a descriptive name, such as `SRE Challenge Release Please`, and choose an expiration period.
4. Set the resource owner to `nolan-m` and grant access only to the `SRE-Challenge` repository.
5. Grant these repository permissions:
	- **Contents:** Read and write
	- **Pull requests:** Read and write
	- **Metadata:** Read-only
6. Generate the token and copy it immediately. Never commit it or share it.

Store it as a repository secret:

1. Open **SRE-Challenge → Settings → Secrets and variables → Actions**.
2. Select **New repository secret**.
3. Set the name to `RELEASE_PLEASE_TOKEN` and paste the token as the secret value.

Use an expiration and rotation process appropriate for the repository. The existing version tag will not automatically rerun deployment after this secret is added; verify the setup with the next release cycle.

## Infrastructure Changes

The Terraform workflow initializes, formats, validates, and plans with `terraform/environments/dev.tfvars`. Changes merged to `main` automatically apply the reviewed plan through the protected `terraform-apply` environment. Manual dispatch also creates a plan, but applies it only when the `apply` input is enabled; the input has no effect on push-triggered runs.

## Runner Requirements

The deployment uses the GitHub-hosted `ubuntu-latest` runner, which provides Docker and outbound access to GitHub and Google APIs. The workflow configures gcloud, explicitly installs `gke-gcloud-auth-plugin`, temporarily appends the runner's public `/32` to the existing GKE master authorized networks, and restores the original allowlist in an `always()` cleanup step. The GKE control-plane access remains restricted; the workflow refuses to modify a cluster with no existing allowlist and never uses `0.0.0.0/0`.

### Temporary GKE Access

GitHub-hosted runner IP addresses are dynamic, so they cannot be permanently included in Terraform’s `master_authorized_networks`. The tag deployment workflow handles this temporarily:

1. It obtains the runner’s public egress IP from `api.ipify.org`.
2. It reads the cluster’s current master authorized CIDRs.
3. It appends the runner IP as a `/32` and updates the cluster.
4. It retrieves GKE credentials and deploys the digest-pinned manifest.
5. An `if: always()` cleanup step restores the original CIDR list, even when deployment or rollout fails.

This workflow preserves the existing allowlist and does not disable master authorized networks. The update is not atomic with deployment, so concurrent cluster access or Terraform applies should be avoided during the deployment window. If the GitHub runner is forcibly terminated before cleanup runs, inspect and restore the allowlist manually or run Terraform with the intended `master_authorized_networks` value.

### Future Improvement

Move deployment jobs to a dedicated self-hosted runner inside the GCP VPC. A VPC-hosted runner with a stable egress path can reach the private GKE control plane directly, remove the temporary GitHub IP allowlisting step, and reduce the risk of cleanup failure. The runner should be dedicated to this repository, regularly patched or rebuilt, and assigned the existing `self-hosted`, `linux`, `x64`, and `gcp` labels.

## Access Controls

The bootstrap Terraform restricts the OIDC provider to the configured repository, the configured branch, and release tags beginning with `v`. GitHub receives short-lived credentials only through Workload Identity Federation. Configure `terraform-apply` and `terraform-destroy` as protected environments with appropriate reviewers before using the corresponding workflows.

After changing the OIDC condition, apply `terraform/state-bootstrap` once with administrator credentials before retrying a tag deployment. The tag workflow will continue to fail authentication until the provider condition is updated in Google Cloud.
