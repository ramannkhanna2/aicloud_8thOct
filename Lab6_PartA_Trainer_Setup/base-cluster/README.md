# Lab 6 — Base Amazon EKS cluster (trainer setup)

This Terraform configuration creates the **base EKS environment** for the Lab 6 GPU/Karpenter/KServe work:

- A dedicated VPC across three eligible Availability Zones
- Public and private subnets, internet gateway and one NAT Gateway
- An EKS cluster running Kubernetes 1.36 by default
- EKS-managed VPC CNI, CoreDNS, kube-proxy, and EKS Pod Identity Agent add-ons
- A small non-GPU managed node group (two `t3.large` nodes by default) for system pods and the later Karpenter controller
- EKS OIDC provider enabled for later IRSA setup
- Subnet and cluster discovery tags to support the later Karpenter setup
- EKS API endpoint access restricted to the public CIDRs you configure

**This code does not install Karpenter, NVIDIA GPU Operator, KServe or KEDA and does not create GPU instances.** Those should be installed in later trainer-setup steps. This avoids unexpectedly starting expensive GPU instances before they are needed.

## Prerequisites

1. Terraform 1.14.3 or newer (compatible with the pinned Terraform modules in this package).
2. AWS CLI v2 configured with credentials for the target training account.
3. `kubectl` installed.
4. An AWS identity permitted to create EKS, VPC/networking, EC2, IAM roles/policies/OIDC provider, and CloudWatch Logs resources. Organization-level SCPs or permission boundaries may still restrict creation.
5. Confirm sufficient quotas for EKS clusters, EC2 instances, VPC elastic IPs, and NAT Gateways.

The default region is `us-east-1`. The Kubernetes minor version defaults to `1.36`, which AWS lists as supported as of October 2026. Check compatibility before changing Kubernetes version, Karpenter, or KServe versions.

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

Alternatively, install it from Windows PowerShell with `winget install --id Kubernetes.kubectl -e --source winget`, then reopen Git Bash so the updated Windows `PATH` is loaded.

## Install and verify Helm

The trainer addon scripts use Helm to install Karpenter, the NVIDIA device plugin, KEDA, and Prometheus. From Git Bash, install the Windows binary into your user tools directory:

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

Do not run `get_helm.sh` on Windows Git Bash; it tries to install into `/usr/local/bin` with `sudo`.

## Install and verify eksctl

The Karpenter bootstrap uses `eksctl` to create the controller IAM service account. Install the official Windows AMD64 release from Git Bash:

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

The scripts also require `curl` and `envsubst`.

## 1. Confirm AWS credentials

```bash
aws sts get-caller-identity
aws configure get region
terraform version
```

The identity returned by `aws sts get-caller-identity` is the identity that Terraform will use. The EKS module grants this cluster creator administrator access to the new cluster; use an appropriate trainer/admin identity.

## 2. Configure the endpoint access CIDR

For this temporary training setup, keep the public EKS API endpoint open to participant networks by using:

```hcl
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
```

This allows network connectivity from any public IPv4 address; participants still need valid AWS IAM/EKS permissions. Restrict this to the trainer or training-network CIDR for any shared, long-lived, or production environment.

## 3. Initialize, validate and review

Run these commands from this directory:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out lab6.tfplan
```

Review the plan before applying. Confirm the region, allowed endpoint CIDR, VPC, NAT Gateway, EKS cluster and two non-GPU EC2 nodes are what you expect. Terraform downloads the pinned modules and provider during `terraform init`.

## 4. Create the cluster

```bash
terraform apply lab6.tfplan
```

Cluster and managed node group creation may take several minutes. When complete, configure kubectl:

```bash
aws eks update-kubeconfig --region us-east-1 --name ai-cloud-lab6
kubectl get nodes
kubectl get pods --all-namespaces
```

If you override `region` or `cluster_name`, use those values instead. The Terraform output `configure_kubectl` prints the matching command.

Expected baseline: two Ready non-GPU worker nodes and the normal `kube-system` pods. No GPU node should exist yet.

## 5. Notes for the later Karpenter section

The configuration enables the cluster OIDC provider and tags the cluster and subnets with `karpenter.sh/discovery = ai-cloud-lab6` (or your configured cluster name). The addon setup included in the parent package uses that same discovery value and OIDC provider. This base configuration deliberately does not create GPU nodes or install Karpenter, the GPU NodeClass/NodePool, NVIDIA device plugin, KServe, KEDA, or Prometheus.

## Cost and cleanup

There are AWS charges while this infrastructure remains deployed, including the EKS control plane, two EC2 worker nodes, one NAT Gateway, EBS volumes, and any log/data transfer charges. GPU instances are not created by this configuration, but a later Karpenter/GPU test can incur substantial charges.

For a same-cluster retest, return to the package root and remove the externally installed Part A addons first:

```bash
CONFIRM_CLEANUP=DELETE_LAB6_RESOURCES \
bash trainer_addons/cleanup_part_a.sh
```

If participant namespaces were created, include them:

```bash
PARTICIPANT_NAMESPACES=trainee-01,trainee-02 \
CONFIRM_CLEANUP=DELETE_LAB6_RESOURCES \
bash trainer_addons/cleanup_part_a.sh
```

The cleanup script removes Helm/Kubernetes addons and Karpenter CloudFormation resources, but it does not remove the Terraform-managed EKS cluster or VPC. After cleanup, rerun `bash trainer_addons/install_part_a.sh` to test the addon setup again.

For a complete teardown after the environment will no longer be reused:

```bash
cd base-cluster
terraform plan -destroy -out lab6-destroy.tfplan
# Review the destroy plan before continuing.
terraform apply lab6-destroy.tfplan
```

Do not destroy the base cluster while later labs still depend on it.
