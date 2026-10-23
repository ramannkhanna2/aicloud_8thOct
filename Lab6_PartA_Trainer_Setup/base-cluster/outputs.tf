output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS Region containing the EKS cluster."
  value       = var.region
}

output "configure_kubectl" {
  description = "Run this command to add the cluster to your local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint URL."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for the later Karpenter/IRSA setup."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC created for the Lab 6 EKS cluster."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs intended for EKS worker nodes and Karpenter-provisioned nodes."
  value       = module.vpc.private_subnets
}

output "system_node_group_name" {
  description = "Name of the non-GPU managed node group."
  value       = try(module.eks.eks_managed_node_groups["system"].node_group_name, null)
}
