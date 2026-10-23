#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

for cmd in aws kubectl helm eksctl curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: required command not found: $cmd" >&2; exit 1; }
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CLUSTER_STATUS="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'cluster.status' --output text)"
[[ "$CLUSTER_STATUS" == "ACTIVE" ]] || { echo "ERROR: EKS cluster $CLUSTER_NAME is not ACTIVE (status=$CLUSTER_STATUS)." >&2; exit 1; }
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl get nodes

# Step 2: Create the upstream Karpenter IAM policies, node role, and interruption queue.
# The template version is pinned to the matching Karpenter chart version.
CFN_FILE="$(mktemp)"
trap 'rm -f "$CFN_FILE"' EXIT
CFN_URL="https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml"
curl -fsSL "$CFN_URL" -o "$CFN_FILE"
aws cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "$CFN_FILE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"

NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
NODE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${NODE_ROLE_NAME}"
CONTROLLER_ROLE_NAME="${CLUSTER_NAME}-karpenter"
CONTROLLER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${CONTROLLER_ROLE_NAME}"

# Associate the Karpenter controller role with the cluster OIDC provider.
# --role-only leaves Kubernetes ServiceAccount creation to the Helm chart.
POLICY_NAMES=(
  "KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}"
  "KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}"
  "KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}"
  "KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}"
  "KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}"
  "KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}"
)
if ! aws iam get-role --role-name "$CONTROLLER_ROLE_NAME" >/dev/null 2>&1; then
  IAM_ARGS=(eksctl create iamserviceaccount
    --cluster "$CLUSTER_NAME" --region "$AWS_REGION"
    --namespace "$KARPENTER_NAMESPACE" --name karpenter
    --role-name "$CONTROLLER_ROLE_NAME" --role-only --approve)
  for policy_name in "${POLICY_NAMES[@]}"; do
    IAM_ARGS+=(--attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}")
  done
  "${IAM_ARGS[@]}"
fi
# Ensure the six current Karpenter controller policies are attached, including on a rerun.
for policy_name in "${POLICY_NAMES[@]}"; do
  aws iam attach-role-policy \
    --role-name "$CONTROLLER_ROLE_NAME" \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
done

# Let Karpenter-provisioned Linux EC2 nodes register with this API-mode EKS cluster.
if ! aws eks describe-access-entry --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --principal-arn "$NODE_ROLE_ARN" >/dev/null 2>&1; then
  aws eks create-access-entry \
    --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --principal-arn "$NODE_ROLE_ARN" --type EC2_LINUX
fi

# Install the pinned Karpenter controller. Zonal Shift is disabled because this
# teaching cluster does not enable EKS Zonal Shift; interruption queue support remains configured.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "$KARPENTER_VERSION" \
  --namespace "$KARPENTER_NAMESPACE" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "settings.enableZonalShift=false" \
  --set 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn='"${CONTROLLER_ROLE_ARN}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait --timeout 10m

kubectl rollout status deployment/karpenter -n "$KARPENTER_NAMESPACE" --timeout=300s
echo "Step 2 complete: Karpenter is installed in namespace $KARPENTER_NAMESPACE."
echo "Karpenter Node role: $NODE_ROLE_ARN"
echo "Karpenter Controller role: $CONTROLLER_ROLE_ARN"
