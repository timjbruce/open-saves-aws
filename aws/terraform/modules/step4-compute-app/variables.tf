variable "region" {
  description = "AWS region"
  type        = string
}

variable "architecture" {
  description = "Architecture to deploy (amd64 or arm64)"
  type        = string
  default     = "amd64"
  
  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "Architecture must be one of: amd64, arm64."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Open Saves"
  type        = string
  default     = "open-saves"
}

variable "eks_endpoint" {
  description = "Endpoint for EKS control plane"
  type        = string
}

variable "eks_ca_certificate" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  type        = string
}

variable "oidc_provider" {
  description = "OIDC provider URL for the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

variable "ecr_repo_uri" {
  description = "URI of the ECR repository"
  type        = string
}

variable "dynamodb_table_arns" {
  description = "ARNs of the DynamoDB tables"
  type        = list(string)
}

variable "dynamodb_table_names" {
  description = "Names of the DynamoDB tables"
  type = object({
    stores   = string
    records  = string
    metadata = string
  })
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "redis_endpoint" {
  description = "Endpoint of the ElastiCache Redis cluster"
  type        = string
}

variable "parameter_store_name" {
  description = "Name of the Parameter Store parameter containing the configuration"
  type        = string
  default     = "/open-saves/dev/config"
}
