# Application Recovery Runbook

Use this runbook when the application is unavailable, unhealthy, or a deployment has failed. It focuses on non-destructive recovery. Do not destroy the cluster or Terraform resources as a first response.

## Scope and Service Details

- Primary GKE cluster: `nolan-sre` (region `us-central1`)
- Secondary (failover) GKE cluster: `nolan-sre-secondary` (region `us-east1`)
- Namespace: `nolan-sre` (identical in both clusters)
- Deployment: `nolan-sre`
- Service: `nolan-sre` (annotated with a standalone NEG backing the global load balancer)
- Container: `nginx`
- Application protocol: HTTP
- Global load balancer: single static IP, backend service `nolan-sre-backend`, no domain or TLS

Set the project and connect to a cluster (repeat for the other region as needed):

```bash
gcloud config set project nolan-sre-challenge
gcloud container clusters get-credentials nolan-sre \
  --region us-central1 \
  --project nolan-sre-challenge

gcloud container clusters get-credentials nolan-sre-secondary \
  --region us-east1 \
  --project nolan-sre-challenge
```

## 1. Establish Impact

For a quick read-only summary of both clusters, workload status, backend health, and a live LB check in one command:

```bash
./scripts/check-health.sh
```

Check the Pods, rollout, and Service on the affected cluster (both clusters run the same workload active-active):

```bash
kubectl -n nolan-sre get pods -o wide
kubectl -n nolan-sre get deployment nolan-sre
kubectl -n nolan-sre rollout status deployment/nolan-sre --timeout=5m
kubectl -n nolan-sre get service nolan-sre
```

A healthy baseline is three ready Pods, a completed rollout, and populated Service endpoints. Since both regions serve traffic simultaneously, also check whether the other region is absorbing load normally (see Section 5).

Check recent events:

```bash
kubectl -n nolan-sre get events --sort-by=.lastTimestamp
```

## 2. Diagnose Pod Failures

For Pods in `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, or another non-ready state:

```bash
kubectl -n nolan-sre describe pod POD_NAME
kubectl -n nolan-sre logs POD_NAME -c nginx --tail=200
kubectl -n nolan-sre logs POD_NAME -c nginx --previous --tail=200
```

Common causes:

- `Pending`: scheduling, topology, quota, or resource constraints.
- `ImagePullBackOff`: invalid image reference, missing Artifact Registry access, or a missing digest.
- `CrashLoopBackOff`: application startup failure or repeated liveness-probe failure.
- `0/1 Ready`: the readiness probe cannot successfully fetch `/` on port 80.

Check the rollout history and current image:

```bash
kubectl -n nolan-sre rollout history deployment/nolan-sre
kubectl -n nolan-sre get deployment nolan-sre \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="nginx")].image}'
echo
```

## 3. Test the Service Internally

Confirm that the Service has ready endpoints:

```bash
kubectl -n nolan-sre get endpoints nolan-sre
kubectl -n nolan-sre get endpointslices
```

If endpoints exist, test the Service from inside the cluster:

```bash
kubectl -n nolan-sre run curl-test \
  --rm -i --restart=Never \
  --image=curlimages/curl \
  -- curl --fail --silent --show-error http://nolan-sre/
```

If the cluster cannot pull `curlimages/curl`, use port forwarding instead:

```bash
kubectl -n nolan-sre port-forward service/nolan-sre 8080:80
```

In another terminal:

```bash
curl --fail --verbose http://127.0.0.1:8080/
```

If the internal test fails, continue investigating the Pods, Service selectors, endpoints, and NetworkPolicies. If it succeeds, continue with load-balancer diagnosis.

## 4. Recover a Failed Application Release

Use a previously verified immutable image digest. This deploys the known-good application without rebuilding or applying Terraform:

```bash
./scripts/deploy.sh \
  --image-reference us-central1-docker.pkg.dev/nolan-sre-challenge/nolan-sre/nolan-sre@sha256:KNOWN_GOOD_DIGEST
```

Wait for the rollout:

```bash
kubectl -n nolan-sre rollout status deployment/nolan-sre --timeout=5m
kubectl -n nolan-sre get pods
kubectl -n nolan-sre rollout history deployment/nolan-sre
```

Do not roll back to a mutable tag. Use a digest that has already been verified in Artifact Registry or in a previous deployment summary.

## 5. Diagnose External Access

The application is served by a single global external HTTP load balancer with standalone NEG backends in both regions (no per-cluster Ingress). List the backend service and check its health per region:

```bash
gcloud compute backend-services list \
  --project nolan-sre-challenge

gcloud compute backend-services get-health nolan-sre-backend \
  --global \
  --project nolan-sre-challenge
```

Each entry reports the zone, NEG, and `healthState` (`HEALTHY`, `UNHEALTHY`, or `UNKNOWN`). A fully healthy baseline shows `HEALTHY` for endpoints in both `us-central1` and `us-east1` zones.

Get the load balancer's static IP and test it over HTTP (no TLS is configured):

```bash
terraform -chdir=terraform output -raw load_balancer_ip
curl --fail --verbose http://LOAD_BALANCER_IP/
```

If a backend is `UNKNOWN`, allow time for GKE to synchronize the NEG and health check. If it is `UNHEALTHY`, inspect that region's Service endpoints and readiness probes; traffic should already be flowing from the other, healthy region without any manual DNS or configuration change.

## 6. Regional Failover

Both clusters are active-active behind the same global load balancer, so a single-region failure is expected to self-heal without intervention once that region's backends report `UNHEALTHY` (Section 5). Use this section to confirm and, if needed, test that behavior.

Confirm which regions are currently healthy:

```bash
gcloud compute backend-services get-health nolan-sre-backend --global --project nolan-sre-challenge
```

To run a non-destructive failover drill (drains one region's replicas, confirms the backend goes `UNHEALTHY`, then restores it and confirms recovery):

```bash
./scripts/simulate-failover.sh --target primary
./scripts/simulate-failover.sh --target secondary
```

The script never touches Terraform state, master-authorized-networks, or DNS, and requires typing `FAILOVER` to confirm unless `--force` is passed. Use `--no-restore` to leave a region drained for extended testing, then restore manually with `kubectl -n nolan-sre scale deployment/nolan-sre --replicas=N`.

If a full regional outage does not recover automatically within a few minutes of the region reporting healthy again, check the HPA (`kubectl -n nolan-sre get hpa`), node/pod scheduling in that cluster, and the backend service's health check configuration in `terraform/load_balancer.tf`.

## 7. Check Monitoring

Review the Cloud Monitoring links in [Architecture](architecture.md) for request rate, 5xx errors, p95/p99 latency, CPU saturation, restart count, alerts, and the availability SLO.

Correlate an alert with:

```bash
kubectl -n nolan-sre get pods -o wide
kubectl -n nolan-sre get events --sort-by=.lastTimestamp
kubectl -n nolan-sre describe deployment nolan-sre
```

Check the SLO and alert timestamps before and after a rollback to confirm recovery.

## 8. Escalate or Stop

Stop automated changes and escalate when:

- All replicas are unavailable in both regions after a known-good digest rollback.
- Both regions' backends remain `UNHEALTHY` after endpoints and readiness probes are healthy.
- Terraform reports drift or proposes destroying shared infrastructure.
- The issue affects the entire GCP region or control plane in a way that also threatens the other region (e.g. a shared dependency).
- The known-good image cannot be retrieved.

Capture the rollout revision, image digest, Pod events, backend-service health per region, alert names, and timestamps for the incident record.
