data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # AWS documents certain AZ IDs where EKS control-plane placement is unsupported.
  # AZ IDs, unlike AZ names, are consistent across accounts.
  unsupported_az_ids_by_region = {
    "us-east-1"    = ["use1-az3"]
    "us-west-1"    = ["usw1-az2"]
    "ca-central-1" = ["cac1-az3"]
  }

  eligible_az_names = [
    for index, name in data.aws_availability_zones.available.names : name
    if !contains(
      lookup(local.unsupported_az_ids_by_region, var.region, []),
      data.aws_availability_zones.available.zone_ids[index]
    )
  ]

  # Three AZs give the EKS control plane and workloads subnet/AZ resilience.
  azs = slice(local.eligible_az_names, 0, 3)

  cluster_name = var.cluster_name

  common_tags = {
    Project     = "AI for Cloud Engineers"
    Lab         = "6"
    ManagedBy   = "Terraform"
    Environment = "training"
  }

  public_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index)
  ]

  private_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index + 10)
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_dns_support   = true
  enable_dns_hostnames = true

  # One NAT Gateway keeps the lab less expensive than one NAT Gateway per AZ.
  # Private worker nodes use it to download container images and reach AWS APIs.
  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "karpenter.sh/discovery" = local.cluster_name
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = local.cluster_name
  }

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Public API access is limited to the CIDRs supplied in terraform.tfvars.
  # Private access allows tools within the VPC to reach the API as well.
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true
  enabled_log_types                        = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days   = 7

  addons = {
    vpc-cni = {
      before_compute = true
    }
    coredns    = {}
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Karpenter's EC2NodeClass discovers this security group by tag when it
  # launches worker nodes in the private subnets.
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  eks_managed_node_groups = {
    system = {
      name            = "${local.cluster_name}-system"
      use_name_prefix = false

      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = [var.system_node_instance_type]
      disk_size      = 50

      min_size     = var.system_node_min_size
      desired_size = var.system_node_desired_size
      max_size     = var.system_node_max_size

      # Keep system and later Karpenter controller pods on these non-GPU nodes.
      subnet_ids = module.vpc.private_subnets
      labels = {
        "workload-type" = "system"
      }
    }
  }

  # These discovery tags allow the separate Lab 6 Karpenter setup to find the
  # cluster and subnets. Karpenter itself and GPU nodes are intentionally not
  # installed/created by this base-cluster configuration.
  cluster_tags = merge(local.common_tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })

  tags = local.common_tags
}
