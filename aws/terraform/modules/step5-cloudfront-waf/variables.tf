variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "load_balancer_dns" {
  description = "DNS name of the load balancer"
  type        = string
}

variable "load_balancer_arn" {
  description = "ARN of the load balancer"
  type        = string
  default     = ""  # This will be populated after the load balancer is created
}

variable "architecture" {
  description = "Architecture (amd64 or arm64)"
  type        = string
  default     = "arm64"
}

variable "service_account_role_arn" {
  description = "ARN of the service account role for S3 bucket policy"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  type        = string
}

# Provider for CloudFront WAF which must be in us-east-1
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
