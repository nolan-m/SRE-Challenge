# Overview



Thank you for taking the extra time to complete this challenge.  The solution you provide will be used to help asses your ability to create a working solution based on a real-world use case.  We know your time is valuable, so please spend as much time as you think is appropriate (2-10 hours).



# Challenge



Welcome, you are the newest member of the DynamicEnablement team! You have been hand picked because of your ability to implement DevOps principles in a meaningful way and maximize value.



The DynamicEnablement team has created an app that will provide the answer to everything, but they are not sure how to deploy, scale, or even monitor.  As the SRE, they rely on you to guide them down this path and trust that you will make sure their product is "reliable".



The development team has provided their container for you, and now it is up to you to configure the rest.



As you design and deploy your solution, please make sure you keep these concepts in mind:

* Is everything automated? (IaC, CI/CD)

* Do I have security in place?

* How will this scale? (Cluster)

* How am I notified when a problem occurs?

* What is my reliability? (Monitoring and dashboard)

* How can I improve my reliability, or do I need to?



Ideally, the solution would be in GCP, however AWS would also be acceptable.



A complete solution should include:

* Infrastructure deployed using IaC

* Service deployed

* Automated deployment pipeline

* Monitoring

* SLI/SLO dashboard



## Production GKE implementation



This repository contains a production-oriented deployment for the static NGINX site. The application serves `/` on TCP port 80 from the stock `nginx` image.



* [Architecture](docs/architecture.md)

* [Deployment guide](docs/deployment.md)

* [Resilience and day-2 operations](docs/operations.md)

* [Monitoring and SLOs](docs/monitoring.md)

* [Dev Container setup](docs/dev-container.md)



The Terraform configuration provisions a regional GKE Autopilot cluster with private nodes, VPC-native networking, Cloud NAT, Workload Identity Federation, control-plane authorized networks, Artifact Registry, and a default GKE Ingress with an ephemeral external IP. User-managed Spot node pools are not available in Autopilot; use GKE Standard with separate regular and Spot pools if Spot placement becomes a hard requirement.







4 golden signal for monitoring

 latency, traffic, errors, and saturation



## GitHub Actions delivery



The application pipeline runs validation on pull requests and uses `release-please` on `main` to derive semantic versions from Conventional Commits:

Workflow boundaries are explicit:

* `terraform.yaml` runs automatically only when `terraform/**` changes. Manual dispatch remains available for reviewed plans and applies.
* `release-deploy.yaml` runs for `app/**`, `Dockerfile`, and `kubernetes/**` changes.
* A Kubernetes-only change builds and deploys one new SHA-tagged immutable image; it does not create an application release unless the commit uses a releasable Conventional Commit.

Therefore, changes under `kubernetes/**` belong to `release-deploy.yaml`, not `terraform.yaml`.



* `fix:` creates a patch release.

* `feat:` creates a minor release.

* A breaking change creates a major release.



After a release PR is merged, the deployment job builds one image and publishes both `sha-<commit>` and the release tag to Artifact Registry. GKE is updated with the resulting immutable `sha256` digest; mutable tags are never used as the Kubernetes deployment reference.



### Bootstrap requirements

Terraform state is stored remotely in the protected GCS bucket
`nolan-sre-challenge-tfstate`. Bootstrap that bucket once before initializing
the main Terraform configuration:

```bash
./scripts/bootstrap-state.sh --project-id nolan-sre-challenge
```

The script adds the active gcloud account and GitHub deployer to the bucket IAM
policy, then prompts before copying existing local state to
`gs://nolan-sre-challenge-tfstate/terraform/state`. The bucket is versioned,
uses uniform bucket-level access, blocks public access, and cannot be destroyed
by Terraform.



1. Apply Terraform with `github_repository` set to the repository's `OWNER/REPOSITORY` value and a trusted `master_authorized_networks` CIDR.

2. Configure these GitHub Actions variables from Terraform outputs:

`GCP_PROJECT_ID` = "
`GCP_REGION` = "cental1"
`PROJECT_NAMESPACE` = "nolan-sre"
`GCP_WIF_PROVIDER` = "projects/93178190172/locations/global/workloadIdentityPools/github-actions/providers/github-oidc"
`GCP_DEPLOYER_SERVICE_ACCOUNT` = github-actions-deployer@nolan-sre-challenge.iam.gserviceaccount.com
TF_VAR_MASTER_AUTHORIZED_NETWORKS = 

3. Run deployment jobs on a patched self-hosted runner in the GCP VPC with labels `self-hosted`, `linux`, `x64`, and `gcp`. The runner requires Docker, `gcloud`, `kubectl`, outbound NAT access to GitHub and Google APIs, and network access to the GKE control plane.

4. Configure a protected `terraform-apply` GitHub environment before using the manually dispatched Terraform workflow.



Authentication uses GitHub OIDC and short-lived Google Cloud credentials. No service-account JSON key is stored in GitHub. Do not add `0.0.0.0/0` to GKE master authorized networks.



To deploy an existing image locally without applying Terraform or rebuilding it, use `scripts/deploy.sh --image-reference REGION-docker.pkg.dev/PROJECT/REPOSITORY/IMAGE@sha256:DIGEST`. Roll back by supplying a previously verified digest and checking `kubectl rollout status` and `kubectl rollout history`.
