#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
command -v kubectl >/dev/null 2>&1 || { echo 'ERROR: kubectl is required.' >&2; exit 1; }

# Apply EC2NodeClass before NodePool so the NodePool can become Ready immediately.
# This is the Part A Step 4 prerequisite and the NodePool is the Part A Step 3 resource.
TMP_NODECLASS="$(mktemp)"
trap 'rm -f "$TMP_NODECLASS"' EXIT
CLUSTER_NAME="$CLUSTER_NAME" envsubst < "$SCRIPT_DIR/manifests/gpu-ec2nodeclass.yaml.template" > "$TMP_NODECLASS"
kubectl apply -f "$TMP_NODECLASS"
kubectl apply -f "$SCRIPT_DIR/manifests/gpu-nodepool.yaml"

echo 'Waiting for EC2NodeClass/default to become Ready...'
kubectl wait --for=condition=Ready ec2nodeclass/default --timeout=300s
echo 'Waiting for NodePool/gpu-lab to become Ready...'
kubectl wait --for=condition=Ready nodepool/gpu-lab --timeout=300s
kubectl get ec2nodeclass default
kubectl get nodepool gpu-lab

echo 'GPU NodePool/NodeClass created. No GPU instance should be launched until a GPU workload is scheduled.'
