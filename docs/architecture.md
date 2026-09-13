# Architecture

## Infrastructure

The platform runs in Google Cloud:

- A custom regional VPC contains a GKE subnet with separate secondary ranges for Pods and Services.
- Cloud Router and Cloud NAT provide controlled outbound access for private nodes.
- Regional Autopilot GKE uses private nodes, a private control-plane peering range, a regular release channel, and master authorized networks for control-plane access.
- Artifact Registry stores application images.
- A GKE Ingress provisions the external HTTP load balancer. The application Service remains `ClusterIP` inside the cluster.
- Terraform state is stored in a versioned GCS bucket with uniform bucket-level access, public access prevention, and deletion protection.

The state-bootstrap Terraform configuration owns the state bucket IAM, Workload Identity Pool and provider, and GitHub service accounts. Application Terraform owns the runtime infrastructure.

## Application Runtime

The Kubernetes manifest creates the `nolan-sre` namespace, service account, Deployment, ClusterIP Service, Ingress, HorizontalPodAutoscaler, PodDisruptionBudget, and NetworkPolicies.

The Deployment starts with three replicas and uses a rolling update with zero unavailable replicas and one surge replica. Images are pinned by SHA-256 digest. Readiness and liveness probes protect traffic and restart unhealthy containers.

## Reliability

Reliability controls include:

- Three minimum replicas and a PodDisruptionBudget requiring two available Pods.
- Topology spreading across zones and hostnames.
- Readiness, liveness, and graceful pre-stop behavior.
- GKE maintenance windows and deletion protection.
- Immutable image references and rollout verification.
- A 30-day, 99.9% request-based availability SLO.

The deployment process waits for rollout completion before reporting success. A failed rollout should be investigated with Pod events, readiness failures, recent revisions, and ingress/backend health.

## Scaling

The HorizontalPodAutoscaler scales from three to ten replicas based on average CPU utilization, targeting 60%. Scale-up is immediate and scale-down is deliberately stabilized for five minutes. Autopilot and vertical pod autoscaling manage cluster capacity and resource recommendations while the workload declares CPU and memory requests and limits.

The subnet reserves independent ranges for nodes, Pods, and Services. These ranges should be sized for the expected cluster and workload growth before production use.

## Security

Security boundaries include:

- Private GKE nodes and restricted master authorized networks. `0.0.0.0/0` is never acceptable.
- GitHub OIDC with repository and branch attribute conditions.
- Short-lived credentials rather than stored service-account keys.
- Workload Identity for Google Cloud access.
- Uniform bucket-level access, public access prevention, versioned Terraform state, and deletion protection.
- Namespace Pod Security labels, disabled service-account token automounting, a runtime-default seccomp profile, and no privileged container.
- Default-deny ingress and egress NetworkPolicy, with only public gateway ingress and DNS egress allowed by the manifest.
- Non-root execution should be enabled for images that support it; the current NGINX image retains the permissions it requires and drops all capabilities before adding only its required capabilities.

Review IAM roles and network-policy requirements before adding new integrations or egress paths.

## Monitoring and SLO

Cloud Monitoring provisions an SRE dashboard with panels for:

- Traffic: HTTP request rate.
- Errors: HTTP 5xx request rate.
- Saturation: container CPU request utilization.
- Reliability signals: container restart count.

The request-based availability SLO measures successful HTTP 200 requests over a rolling 30-day window with a 99.9% goal. Configured alert policies notify email channels when 5xx traffic exceeds 1% for five minutes, CPU request utilization exceeds 80% for ten minutes, or containers restart during a five-minute window.

Use the dashboard and alert documentation as the starting point for incident response, then correlate load-balancer metrics with ingress, Service endpoints, Pod readiness, resource pressure, and rollout history.
