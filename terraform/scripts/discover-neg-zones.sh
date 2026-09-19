#!/usr/bin/env bash
# External data source: discovers the zones in a region that already have the
# named standalone NEG, so Terraform doesn't need to guess which zones GKE
# Autopilot scheduled Pods into. Reads {"project_id","region","neg_name"} on
# stdin, writes {"zones":"zone-a,zone-b"} (comma-joined, empty if none) on stdout.
set -euo pipefail

eval "$(jq -r '@sh "PROJECT_ID=\(.project_id) REGION=\(.region) NEG_NAME=\(.neg_name)"')"

zones="$(gcloud compute network-endpoint-groups list \
  --project "$PROJECT_ID" \
  --filter="name=${NEG_NAME}" \
  --format="value(zone)" 2>/dev/null \
  | sed -E 's#.*/##' \
  | grep -E "^${REGION}-" \
  | sort -u \
  | paste -sd, - || true)"

jq -n --arg zones "$zones" '{"zones": $zones}'
