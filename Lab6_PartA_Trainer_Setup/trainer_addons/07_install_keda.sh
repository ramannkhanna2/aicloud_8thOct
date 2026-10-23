#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
command -v helm >/dev/null 2>&1 || { echo 'ERROR: helm is required.' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo 'ERROR: kubectl is required.' >&2; exit 1; }

helm repo add kedacore https://kedacore.github.io/charts --force-update
helm repo update kedacore
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace --wait --timeout 10m
kubectl get pods -n keda
echo 'Step 7 complete: KEDA is installed. Prometheus-triggered scaling cannot work until the configured metric is being scraped.'
