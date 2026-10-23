#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

for cmd in aws kubectl helm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  }
done

if [[ "${CONFIRM_CLEANUP:-}" != "DELETE_LAB6_RESOURCES" ]]; then
  echo 'Cleanup is destructive and removes the Part A addons.' >&2
  echo 'To continue, run:' >&2
  echo '  CONFIRM_CLEANUP=DELETE_LAB6_RESOURCES bash trainer_addons/cleanup_part_a.sh' >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CLUSTER_STATUS="$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.status' \
  --output text)"
[[ "$CLUSTER_STATUS" == "ACTIVE" ]] || {
  echo "ERROR: EKS cluster $CLUSTER_NAME is not ACTIVE (status=$CLUSTER_STATUS)." >&2
  exit 1
}

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
CURRENT_CONTEXT="$(kubectl config current-context)"
[[ "$CURRENT_CONTEXT" == *":cluster/${CLUSTER_NAME}" ]] || {
  echo "ERROR: kubectl is using unexpected context: $CURRENT_CONTEXT" >&2
  exit 1
}

# Optional comma-separated participant namespaces, for example:
# PARTICIPANT_NAMESPACES=trainee-01,trainee-02
if [[ -n "${PARTICIPANT_NAMESPACES:-}" ]]; then
  IFS=',' read -r -a namespaces <<< "$PARTICIPANT_NAMESPACES"
  for namespace in "${namespaces[@]}"; do
    namespace="${namespace//[[:space:]]/}"
    [[ -n "$namespace" ]] || continue
    echo "Deleting participant namespace: $namespace"
    kubectl delete namespace "$namespace" --ignore-not-found --wait=true
  done
else
  echo 'No PARTICIPANT_NAMESPACES supplied; participant namespaces/workloads were not deleted.'
fi

# Remove GPU capacity first so Karpenter can terminate any GPU NodeClaims/nodes
# before its controller and AWS IAM resources are removed.
kubectl delete nodepool gpu-lab --ignore-not-found --wait=true

for attempt in {1..60}; do
  nodeclaim_count="$(kubectl get nodeclaims --no-headers 2>/dev/null | awk 'NF {count++} END {print count+0}')"
  [[ "$nodeclaim_count" == "0" ]] && break
  echo "Waiting for $nodeclaim_count Karpenter NodeClaim(s) to terminate..."
  sleep 10
done

remaining_nodeclaims="$(kubectl get nodeclaims --no-headers 2>/dev/null | awk 'NF {count++} END {print count+0}')"
[[ "$remaining_nodeclaims" == "0" ]] || {
  echo "ERROR: Karpenter NodeClaims remain after waiting; refusing to remove Karpenter." >&2
  exit 1
}

kubectl delete ec2nodeclass default --ignore-not-found --wait=true

# Remove Helm-installed addons. Uninstalling releases is safe to repeat.
helm uninstall nvidia-device-plugin --namespace kube-system || true
kubectl delete -f "$SCRIPT_DIR/manifests/prometheus-service-alias.yaml" --ignore-not-found || true
helm uninstall prometheus --namespace istio-system || true
kubectl delete namespace istio-system --ignore-not-found --wait=true

helm uninstall keda --namespace keda || true
kubectl delete namespace keda --ignore-not-found --wait=true

helm uninstall kserve-resources --namespace kserve || true
helm uninstall kserve-crd --namespace kserve || true
kubectl delete namespace kserve --ignore-not-found --wait=true

helm uninstall cert-manager --namespace cert-manager || true
kubectl delete namespace cert-manager --ignore-not-found --wait=true

helm uninstall karpenter --namespace "$KARPENTER_NAMESPACE" || true
kubectl delete namespace "$KARPENTER_NAMESPACE" --ignore-not-found --wait=true

NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
NODE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${NODE_ROLE_NAME}"
aws eks delete-access-entry \
  --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --principal-arn "$NODE_ROLE_ARN" 2>/dev/null || true

# The two CloudFormation stacks own the Karpenter IAM roles/policies and queue.
delete_stack() {
  local stack_name="$1"
  if aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$stack_name" >/dev/null 2>&1; then
    echo "Deleting CloudFormation stack: $stack_name"
    aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$stack_name"
    aws cloudformation wait stack-delete-complete \
      --region "$AWS_REGION" \
      --stack-name "$stack_name"
  else
    echo "CloudFormation stack not found: $stack_name"
  fi
}

delete_stack "eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-karpenter-karpenter"
delete_stack "Karpenter-${CLUSTER_NAME}"

echo
echo 'Part A addon cleanup completed.'
echo 'Terraform-managed EKS/VPC resources were not destroyed.'
echo 'Review and run the following separately when you are ready to remove the cluster:'
echo '  cd base-cluster'
echo '  terraform plan -destroy -out lab6-destroy.tfplan'
echo '  terraform apply lab6-destroy.tfplan'
