#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
command -v helm >/dev/null 2>&1 || { echo 'ERROR: helm is required.' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo 'ERROR: kubectl is required.' >&2; exit 1; }

# Lab 6's sample manifest specifies this DNS name, so place the lab Prometheus
# service in istio-system and expose the expected alias service name.
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace istio-system \
  --values "$SCRIPT_DIR/values/prometheus-values.yaml" \
  --wait --timeout 10m
kubectl apply -f "$SCRIPT_DIR/manifests/prometheus-service-alias.yaml"

kubectl get pods -n istio-system
kubectl get svc prometheus -n istio-system
kubectl get endpoints prometheus -n istio-system

echo 'Step 8 complete. The lab URL should be http://prometheus.istio-system.svc.cluster.local:9090.'
echo 'Verify the prometheus Service has endpoints. If endpoints are empty, inspect the Prometheus Pod labels and Service selector before proceeding.'
