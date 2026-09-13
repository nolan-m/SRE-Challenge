# Development

## Dev Container

The repository includes a Dev Container based on `mcr.microsoft.com/devcontainers/base:ubuntu`. It installs:

- Docker CLI and Docker Engine packages
- Terraform
- Google Cloud CLI
- GKE `gcloud` authentication plugin
- `kubectl`

VS Code extensions are configured for Terraform, Kubernetes, and Google Cloud development.

### Open the Container

1. Install Docker and the VS Code Dev Containers extension on the host.
2. Open the repository in VS Code.
3. Run **Dev Containers: Reopen in Container**.
4. Wait for the image build and post-create setup to finish.

The container uses `/workspaces/SRE-Challenge` as its workspace, mounts the host Docker socket, and makes `scripts/*.sh` executable during creation. The Docker socket allows local image builds from inside the container; use it only with a trusted repository.

## Authenticate to Google Cloud

For local infrastructure or cluster operations, authenticate from the container:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
gcloud auth configure-docker REGION-docker.pkg.dev
```

The account needs the permissions required by the operation. State-bootstrap commands require administrator-level access to create the initial bucket, identities, and IAM bindings.

## Validate Terraform

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=environments/dev.tfvars
```

For state bootstrap, use its own working directory:

```bash
terraform -chdir=terraform/state-bootstrap fmt -check
terraform -chdir=terraform/state-bootstrap init
terraform -chdir=terraform/state-bootstrap validate
```

Do not run `terraform apply` against shared infrastructure without reviewing the plan and confirming the backend and project are correct.

## Build and Smoke Test the Container

The production image is a small NGINX image that copies `app/` into the web root:

```bash
docker build --tag nolan-sre:local .
docker run --detach --name nolan-sre-local --publish 18080:80 nolan-sre:local
curl --fail http://127.0.0.1:18080/
docker rm --force nolan-sre-local
```

The same build and HTTP smoke test run in the PR workflow.

## Work with GKE

After infrastructure exists, fetch cluster credentials and inspect the workload:

```bash
gcloud container clusters get-credentials nolan-sre --region us-central1 --project YOUR_PROJECT_ID
kubectl --namespace nolan-sre get pods,service,ingress
kubectl --namespace nolan-sre describe deployment nolan-sre
```

Use `scripts/deploy.sh` for a complete local deployment. To avoid rebuilding, provide an immutable digest with `--image-reference`. Set `MASTER_AUTHORIZED_IP` to a trusted CIDR before using the deployment or teardown scripts.

## Safe Teardown

`scripts/teardown.sh` deletes the application namespace and Terraform-managed application resources after an explicit `DESTROY` confirmation. It does not remove state-bootstrap resources. Prefer the protected `destroy-application.yaml` workflow for shared environments.
