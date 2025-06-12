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
