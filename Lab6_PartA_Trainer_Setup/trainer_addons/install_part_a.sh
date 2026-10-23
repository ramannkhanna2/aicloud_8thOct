#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"
echo "Preparing Lab 6 add-ons for cluster ${CLUSTER_NAME} in ${AWS_REGION}."
echo 'This assumes the base EKS cluster from ../base-cluster has already been created.'
bash "$SCRIPT_DIR/02_install_karpenter.sh"
bash "$SCRIPT_DIR/03_04_apply_gpu_capacity_config.sh"
bash "$SCRIPT_DIR/05_install_nvidia_device_plugin.sh"
bash "$SCRIPT_DIR/06_install_kserve_standard.sh"
bash "$SCRIPT_DIR/07_install_keda.sh"
bash "$SCRIPT_DIR/08_install_prometheus.sh"
bash "$SCRIPT_DIR/verify_part_a.sh"
echo 'Part A installation flow completed. Review every verification result before the training lab.'
