variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "architecture" {
  description = "Architecture to build for (amd64, arm64, or both)"
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64", "both"], var.architecture)
    error_message = "Architecture must be 'amd64', 'arm64', or 'both'."
  }
}

variable "source_path" {
  description = "Path to the source code directory"
  type        = string
  default     = "/home/ec2-user/projects/open-saves-aws/aws"
}

variable "source_hash" {
  description = "Hash of the source code to trigger rebuilds"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
