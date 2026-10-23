#!/usr/bin/env bash
# Shared defaults for the Lab 6 trainer setup. Override these before running scripts.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export CLUSTER_NAME="${CLUSTER_NAME:-ai-cloud-lab6}"
export KARPENTER_VERSION="${KARPENTER_VERSION:-1.14.0}"
export KARPENTER_NAMESPACE="${KARPENTER_NAMESPACE:-karpenter}"
export KSERVE_VERSION="${KSERVE_VERSION:-v0.20.0}"
