variable "region" {
  description = "AWS region"
  type        = string
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

variable "ecr_repo_uri" {
  description = "URI of the ECR repository"
  type        = string
}

variable "source_path" {
  description = "Path to the source code"
  type        = string
  default     = "../../aws"
}

variable "source_hash" {
  description = "Hash of the source code to trigger rebuilds"
  type        = string
  default     = "initial"
}
