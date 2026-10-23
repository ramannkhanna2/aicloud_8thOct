# Lab 6 — Complete Part A Trainer Setup (EKS + Karpenter + GPU + KServe + KEDA + Prometheus)

This package is based on the uploaded `aicloud_lab6.docx`, specifically **Part A — Trainer setup, Steps 1–8**. It has two stages:

1. `base-cluster/`: Terraform to provision the shared EKS cluster, VPC/private subnets, and inexpensive non-GPU managed node group.
2. `trainer_addons/`: ordered scripts and manifests to install/configure the remaining trainer prerequisites.

## What this package provisions

| Lab 6 Part A | Package components |
|---|---|
| 1. Shared EKS cluster in `us-east-1` | Terraform root module in `base-cluster/` |
| 2. Karpenter controller and IAM bootstrap | `trainer_addons/02_install_karpenter.sh` |
| 3. GPU NodePool called `gpu-lab` | `trainer_addons/manifests/gpu-nodepool.yaml` |
| 4. GPU EC2NodeClass called `default` | `trainer_addons/manifests/gpu-ec2nodeclass.yaml.template` |
| 5. NVIDIA device plugin | `trainer_addons/05_install_nvidia_device_plugin.sh` and its values file |
| 6. KServe Standard mode | `trainer_addons/06_install_kserve_standard.sh` |
| 7. KEDA | `trainer_addons/07_install_keda.sh` |
| 8. Prometheus | `trainer_addons/08_install_prometheus.sh` and an alias Service using the exact DNS name in Lab 6 |

The add-on scripts use versions visible in current upstream documentation at package creation: Karpenter `1.14.0` and KServe `v0.20.0`. KEDA and the NVIDIA device plugin are installed from their upstream Helm repositories without a chart version pin, so those charts resolve to the repository's current version when executed. For repeatable long-lived training environments, record the actual chart versions from `helm list -A` and pin them for later rebuilds.

## Before you run anything

- Use a trainer/admin AWS identity with permission to create EKS/VPC/EC2/IAM/CloudFormation resources and install Kubernetes controllers.
- Install Terraform **1.14.3+**, AWS CLI v2, `kubectl`, Helm 3, `eksctl`, `curl`, Bash, and `envsubst`.
- Confirm Region `us-east-1` quotas, EKS service availability and GPU-family quota/capacity.
- This temporary training setup intentionally uses `0.0.0.0/0` for the public EKS API endpoint so participants can connect from different networks. Restrict this CIDR for any shared, long-lived, or production environment.
- Review the Terraform plan and AWS costs. EKS control plane, two `t3.large` worker nodes, NAT Gateway, load/data transfer and add-ons incur cost even before GPUs are requested.
- A GPU node is **not** created just by creating the NodePool. However, Part B's GPU test Pod and Part C's model can trigger an on-demand G6/G6e instance. GPU charges can be significant.

## Install and verify kubectl on Windows/Git Bash

The AWS CLI configures the kubeconfig, but it does not install `kubectl`. From Git Bash, download the Windows AMD64 binary into your user tools directory:

```bash
mkdir -p "$HOME/bin"
curl.exe -L -o "$HOME/bin/kubectl.exe" "https://dl.k8s.io/release/v1.37.0/bin/windows/amd64/kubectl.exe"
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
```

Open a new Git Bash window and verify:

```bash
kubectl version --client
```

The trainer addon scripts also require Helm 3. From Git Bash, install the Windows binary into your user tools directory:

```bash
mkdir -p "$HOME/bin"
curl.exe -L -o "$HOME/bin/helm-v3.19.0-windows-amd64.tar.gz" "https://get.helm.sh/helm-v3.19.0-windows-amd64.tar.gz"
tar -xzf "$HOME/bin/helm-v3.19.0-windows-amd64.tar.gz" -C "$HOME/bin"
cp "$HOME/bin/windows-amd64/helm.exe" "$HOME/bin/helm.exe"
export PATH="$HOME/bin:$PATH"
grep -qxF 'export PATH="$HOME/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
hash -r
```

Verify:

```bash
helm version
```

The scripts also require `eksctl`. Install the official Windows AMD64 release from Git Bash:

```bash
mkdir -p "$HOME/bin"
curl.exe -L -o "$HOME/bin/eksctl_Windows_amd64.zip" "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Windows_amd64.zip"
unzip -o "$HOME/bin/eksctl_Windows_amd64.zip" -d "$HOME/bin"
rm "$HOME/bin/eksctl_Windows_amd64.zip"
export PATH="$HOME/bin:$PATH"
grep -qxF 'export PATH="$HOME/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
hash -r
```

Verify:

```bash
eksctl version
```

The scripts also require `curl` and `envsubst`; verify all required commands before starting the addon installation.

## Stage 1 — Create the base cluster (Part A Step 1)

Run from a Bash-compatible terminal at the package root:

```bash
cp base-cluster/terraform.tfvars.example base-cluster/terraform.tfvars
# The example is configured for the temporary training setup with 0.0.0.0/0.
cd base-cluster
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out lab6.tfplan
# Review the plan carefully before applying.
terraform apply lab6.tfplan
aws eks update-kubeconfig --region us-east-1 --name ai-cloud-lab6
kubectl get nodes
cd ..
```

The base cluster creates two `t3.large` CPU nodes by default to host system pods/controllers. It tags private subnets and the node security group for Karpenter discovery. It deliberately does not launch GPU instances or install Karpenter/KServe/KEDA/Prometheus.

## Stage 2 — Install Part A Steps 2–8

The scripts require Bash (Linux/macOS, AWS CloudShell, or Git Bash/WSL) and internet access to official AWS/Karpenter/KServe/Helm repositories. In PowerShell, use WSL or Git Bash rather than pasting the scripts into PowerShell.

From the package root:

```bash
bash trainer_addons/install_part_a.sh
```

This runs the Karpenter bootstrap, waits for Karpenter, creates the GPU `EC2NodeClass` and `NodePool`, installs the NVIDIA device plugin, installs KServe Standard mode, installs KEDA, installs Prometheus in `istio-system`, creates the `prometheus` Service alias, then runs verification commands.

Run individual scripts when troubleshooting:

```bash
bash trainer_addons/02_install_karpenter.sh
bash trainer_addons/03_04_apply_gpu_capacity_config.sh
bash trainer_addons/05_install_nvidia_device_plugin.sh
bash trainer_addons/06_install_kserve_standard.sh
bash trainer_addons/07_install_keda.sh
bash trainer_addons/08_install_prometheus.sh
bash trainer_addons/verify_part_a.sh
```

## Expected verification

```bash
kubectl get pods -n karpenter
kubectl get nodepool gpu-lab
kubectl get ec2nodeclass default
kubectl get pods -A | grep -i nvidia
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu'
kubectl get pods -n kserve
kubectl get pods -n keda
kubectl get pods -n istio-system
kubectl get svc prometheus -n istio-system
kubectl get endpoints prometheus -n istio-system
```

- `karpenter` controller should be Running.
- `gpu-lab` NodePool and `default` EC2NodeClass should report Ready.
- Before a GPU workload is scheduled, seeing no GPU EC2 node is expected. Depending on the GPU plugin chart selectors, the device plugin DaemonSet may show zero desired Pods until a GPU node exists.
- KServe and KEDA Pods should be Running/Ready.
- The `prometheus` Service in `istio-system` must have endpoints. This package creates the exact URL used in the lab: `http://prometheus.istio-system.svc.cluster.local:9090`.
- The LLM metric `vllm:num_requests_running` won't exist until the later model workload is deployed and Prometheus successfully scrapes it. Check the metric before expecting KEDA to scale.
- **Check the Part C InferenceService manifest before the learner lab.** Current KServe KEDA examples use the annotation `serving.kserve.io/autoscalerClass: "keda"` to select KEDA, and document the Prometheus scrape annotations (`prometheus.io/scrape`, `prometheus.io/path`, `prometheus.io/port`, `prometheus.io/scheme`) alongside `serving.kserve.io/enable-prometheus-scraping`. The uploaded Part C manifest appears to show only `deploymentMode` and `enable-prometheus-scraping`; if so, update that manifest before expecting the KEDA `ScaledObject` and metric-based scale-out to work. This is a separate workload manifest concern, not an installation step in Part A.

## Important implementation notes

- The original Lab 6 defines Karpenter resources in a simplified way. This package adds the IAM/controller bootstrap and the Karpenter node role mapping that a newly created EKS cluster also needs for Karpenter to launch nodes.
- The cluster uses standard EKS (self-managed Karpenter), not EKS Auto Mode, because Part A explicitly asks for a Karpenter controller, a custom NodePool and EC2NodeClass, and the NVIDIA device plugin.
- The NodeClass uses the official EKS AL2023 latest AMI alias. Karpenter chooses the appropriate accelerated AMI for compatible GPU instance types. For a long-lived/prod system, pin and test AMIs rather than tracking `latest`.
- The trainer installation command applies the EC2NodeClass before the NodePool because the NodePool references that class. They remain distinct files/steps in the package.
- KServe Step 6 uses the official pinned KServe OCI Helm charts and cert-manager, which avoids the upstream shell installer’s MINGW64 OS-detection issue on Windows Git Bash.
- The Prometheus chart is an in-cluster lab deployment with persistence disabled, suitable for the course exercise, not a production monitoring architecture.

## Cost and cleanup

GPU EC2 capacity only starts when requested by the lab workload, but the shared cluster, CPU nodes and NAT Gateway incur ongoing cost. For Part B and later Part C–E, participants should remove only their own workload resources. They must **not** delete the shared EKS cluster, Karpenter, `gpu-lab`, KServe, KEDA or Prometheus; your Lab 6 explicitly says these belong to the shared training environment.

### Remove Part A addons for a same-cluster retest

The addons are outside Terraform, so use the guarded trainer cleanup script before reinstalling Part A addons:

```bash
# Run from the package root. Add participant namespaces if they were created.
PARTICIPANT_NAMESPACES=trainee-01,trainee-02 \
CONFIRM_CLEANUP=DELETE_LAB6_RESOURCES \
bash trainer_addons/cleanup_part_a.sh
```

If no participant namespaces were created:

```bash
CONFIRM_CLEANUP=DELETE_LAB6_RESOURCES \
bash trainer_addons/cleanup_part_a.sh
```

The script removes participant namespaces supplied in `PARTICIPANT_NAMESPACES`, GPU capacity objects, Helm releases, addon namespaces, the Karpenter node access entry, and the Karpenter CloudFormation stacks. It does **not** destroy the Terraform-managed EKS cluster, VPC, NAT Gateway, or CPU node group.

After cleanup, a same-cluster retest can start again with:

```bash
bash trainer_addons/install_part_a.sh
```

### Complete teardown

Only after the addons have been cleaned up and the environment will no longer be reused, remove the Terraform-managed infrastructure:

```bash
cd base-cluster
terraform plan -destroy -out lab6-destroy.tfplan
# Review the destroy plan carefully.
terraform apply lab6-destroy.tfplan
```

Do not run `terraform destroy` between the lab's steps or between labs that reuse this environment. The cleanup script and the Terraform destroy are intentionally separate so GPU nodes and external Karpenter resources are removed before the VPC and EKS cluster.

## Validation scope

I reviewed the package structure and shell-script syntax locally. The AWS resources were **not** deployed from this environment, and Terraform could not be validated against a live AWS account here. You must run `terraform init`, `terraform validate`, and a reviewed plan in your target account before applying. Account IAM boundaries, service quotas, subnet discovery, available G6/G6e capacity and upstream chart changes can affect live installation.

## Official references used

- AWS EKS AI/ML cluster setup with Terraform: https://docs.aws.amazon.com/eks/latest/userguide/ml-cluster-setup-tf.html
- AWS EKS GPU NodePool guide: https://docs.aws.amazon.com/eks/latest/userguide/ml-inference-gpu-nodepool-tf.html
- Karpenter getting started: https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/
- Karpenter EC2NodeClass reference: https://karpenter.sh/docs/concepts/nodeclasses/
- KServe quickstart and Standard-mode install: https://kserve.github.io/website/docs/getting-started/quickstart-guide
- KServe dependencies: https://kserve.github.io/website/docs/install/dependencies
- AWS EKS Prometheus install guide: https://docs.aws.amazon.com/eks/latest/userguide/deploy-prometheus.html
- AWS EKS KEDA autoscaling guide: https://docs.aws.amazon.com/eks/latest/userguide/ml-inference-autoscaling-hpa-keda.html
