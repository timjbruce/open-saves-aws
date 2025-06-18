variable "region" {
  description = "AWS region"
  type        = string
}

variable "architecture" {
  description = "Architecture to deploy (amd64 or arm64)"
  type        = string
  default     = "amd64"
  
  validation {
    condition     = contains(["amd64", "arm64", "both"], var.architecture)
    error_message = "Architecture must be one of: amd64, arm64, both."
  }
}

variable "vpc_id" {
  description = "ID of the VPC"
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

variable "config_path" {
  description = "Path to store the config.yaml file"
  type        = string
  default     = "../config"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}
