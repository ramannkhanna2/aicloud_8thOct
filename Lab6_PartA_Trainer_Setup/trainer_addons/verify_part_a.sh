#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
echo '\n=== EKS worker nodes ==='
kubectl get nodes -o wide
echo '\n=== Step 2: Karpenter ==='
kubectl get pods -n "$KARPENTER_NAMESPACE"
echo '\n=== Steps 3-4: GPU NodePool and EC2NodeClass ==='
kubectl get nodepool gpu-lab
kubectl get ec2nodeclass default
echo '\n=== Step 5: NVIDIA plugin resources ==='
kubectl get pods -A | grep -i nvidia || true
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
echo '\n=== Step 6: KServe ==='
kubectl get pods -n kserve
echo '\n=== Step 7: KEDA ==='
kubectl get pods -n keda
echo '\n=== Step 8: Prometheus ==='
kubectl get pods -n istio-system
kubectl get svc prometheus -n istio-system
kubectl get endpoints prometheus -n istio-system
echo '\nPart A verification commands completed. Confirm controller Pods are Running and the Prometheus Service has endpoints.'
