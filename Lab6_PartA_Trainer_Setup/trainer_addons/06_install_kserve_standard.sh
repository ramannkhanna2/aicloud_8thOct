#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

command -v helm >/dev/null 2>&1 || { echo 'ERROR: helm is required.' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo 'ERROR: kubectl is required.' >&2; exit 1; }

# KServe Standard mode requires cert-manager for webhook certificates.
# Install dependencies with Helm rather than the upstream shell installer so
# this works from Windows Git Bash as well as Linux/macOS.
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  --version v1.17.0 \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 10m

kubectl rollout status deployment/cert-manager -n cert-manager --timeout=300s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=300s

# Install the pinned KServe Standard-mode CRDs and controller resources from
# the official KServe OCI charts. These charts avoid the MINGW64 OS detection
# problem in the release shell installer.
helm upgrade --install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version "$KSERVE_VERSION" \
  --namespace kserve --create-namespace \
  --wait --timeout 10m

helm upgrade --install kserve-resources oci://ghcr.io/kserve/charts/kserve-resources \
  --version "$KSERVE_VERSION" \
  --namespace kserve \
  --set kserve.controller.deploymentMode=Standard \
  --wait --timeout 10m

kubectl wait --for=condition=Established \
  crd/inferenceservices.serving.kserve.io --timeout=300s
kubectl rollout status deployment/kserve-controller-manager \
  -n kserve --timeout=300s
kubectl get pods -n kserve

echo "Step 6 complete: KServe Standard mode ${KSERVE_VERSION} installed with Helm."
