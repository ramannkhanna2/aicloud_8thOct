#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
command -v helm >/dev/null 2>&1 || { echo 'ERROR: helm is required.' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo 'ERROR: kubectl is required.' >&2; exit 1; }

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin --force-update
helm repo update nvdp
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace kube-system \
  --values "$SCRIPT_DIR/values/nvidia-device-plugin-values.yaml" \
  --wait --timeout 10m

kubectl get daemonset -n kube-system nvidia-device-plugin || true
echo 'Step 5 complete. Device-plugin Pods appear on nodes labeled nvidia.com/gpu.present=true; this can be zero before the first GPU node exists.'
