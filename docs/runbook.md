# Application Recovery Runbook

Use this runbook when the application is unavailable, unhealthy, or a deployment has failed. It focuses on non-destructive recovery. Do not destroy the cluster or Terraform resources as a first response.

## Scope and Service Details

- GKE cluster: `nolan-sre`
- Region: `us-central1`
- Namespace: `nolan-sre`
- Deployment: `nolan-sre`
- Service: `nolan-sre`
- Container: `nginx`
- Application protocol: HTTP

Set the project and connect to the cluster:

```bash
gcloud config set project nolan-sre-challenge
gcloud container clusters get-credentials nolan-sre \
  --region us-central1 \
  --project nolan-sre-challenge
```

## 1. Establish Impact

Check the Pods, rollout, Service, and Ingress:

```bash
kubectl -n nolan-sre get pods -o wide
kubectl -n nolan-sre get deployment nolan-sre
kubectl -n nolan-sre rollout status deployment/nolan-sre --timeout=5m
kubectl -n nolan-sre get service nolan-sre
kubectl -n nolan-sre get ingress nolan-sre
```

A healthy baseline is three ready Pods, a completed rollout, populated Service endpoints, and an Ingress with an external IP.

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

If the internal test fails, continue investigating the Pods, Service selectors, endpoints, and NetworkPolicies. If it succeeds, continue with Ingress diagnosis.

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

Inspect the Ingress and its events:

```bash
kubectl -n nolan-sre describe ingress nolan-sre
kubectl -n nolan-sre get ingress nolan-sre -o wide
```

The Ingress should have an external IP and its application backend should report `HEALTHY`:

```bash
kubectl -n nolan-sre get ingress nolan-sre \
  -o jsonpath='{.metadata.annotations.ingress\\.kubernetes\\.io/backends}'
echo
```

Retrieve the application backend name and check its health in the global load balancer:

```bash
gcloud compute backend-services list \
  --project nolan-sre-challenge

gcloud compute backend-services get-health \
  BACKEND_SERVICE_NAME \
  --global \
  --project nolan-sre-challenge
```

Test the provisioned address over HTTP. The current manifest does not configure TLS:

```bash
curl --fail --verbose http://EXTERNAL_IP/
```

If the backend is `Unknown`, allow time for GKE to synchronize the NEG and health check. If it is `UNHEALTHY`, inspect the Ingress events, Service endpoints, readiness probes, and backend health details.

## 6. Check Monitoring

Review the Cloud Monitoring links in [Architecture](architecture.md) for request rate, 5xx errors, p95/p99 latency, CPU saturation, restart count, alerts, and the availability SLO.

Correlate an alert with:

```bash
kubectl -n nolan-sre get pods -o wide
kubectl -n nolan-sre get events --sort-by=.lastTimestamp
kubectl -n nolan-sre describe deployment nolan-sre
```

Check the SLO and alert timestamps before and after a rollback to confirm recovery.

## 7. Escalate or Stop

Stop automated changes and escalate when:

- All replicas are unavailable after a known-good digest rollback.
- The Ingress remains unhealthy after endpoints and readiness probes are healthy.
- Terraform reports drift or proposes destroying shared infrastructure.
- The issue affects the entire GCP region or control plane.
- The known-good image cannot be retrieved.

Capture the rollout revision, image digest, Pod events, Ingress events, backend health, alert names, and timestamps for the incident record. The current design has no cold standby cluster or automatic cross-region failover, so regional recovery requires a separate disaster-recovery procedure.
