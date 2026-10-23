variable "region" {
  description = "AWS Region in which to create the Lab 6 EKS environment."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster and related Lab 6 resources."
  type        = string
  default     = "ai-cloud-lab6"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must start with a letter or digit and contain only letters, digits, hyphens, or underscores (maximum 100 characters)."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. 1.36 is selected for the Lab 6 baseline; confirm add-on compatibility before changing it."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR range for the dedicated Lab 6 VPC."
  type        = string
  default     = "10.60.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Public IPv4 CIDR blocks allowed to reach the EKS Kubernetes API. This temporary training setup may use 0.0.0.0/0; restrict it to the trainer or training-network CIDR for long-lived or production environments."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Provide at least one valid CIDR, normally your public IPv4 address followed by /32."
  }
}

variable "system_node_instance_type" {
  description = "EC2 instance type for the EKS managed node group used for system pods and the later Karpenter controller. GPU nodes are not created by this Terraform configuration."
  type        = string
  default     = "t3.large"
}

variable "system_node_min_size" {
  description = "Minimum number of non-GPU system nodes."
  type        = number
  default     = 2
}

variable "system_node_desired_size" {
  description = "Desired number of non-GPU system nodes."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum number of non-GPU system nodes."
  type        = number
  default     = 3
}
