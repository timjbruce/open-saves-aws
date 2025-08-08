variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "architecture" {
  description = "Architecture for ElastiCache (amd64 or arm64)"
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "Architecture must be either 'amd64' or 'arm64'."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
