variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "open-saves-cluster-new"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "dev-open-saves"
}

variable "namespace" {
  description = "Kubernetes namespace for Open Saves"
  type        = string
  default     = "open-saves"
}

variable "architecture" {
  description = "Architecture to deploy (amd64, arm64, or both)"
  type        = string
  default     = "amd64"
  
  validation {
    condition     = contains(["amd64", "arm64", "both"], var.architecture)
    error_message = "Architecture must be one of: amd64, arm64, both."
  }
}

variable "source_hash" {
  description = "Hash of the source code to trigger rebuilds"
  type        = string
  default     = "initial"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}
