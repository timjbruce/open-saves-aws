variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "architecture" {
  description = "Architecture for compute nodes (amd64 or arm64)"
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "Architecture must be either 'amd64' or 'arm64'."
  }
}

variable "instance_types" {
  description = "Instance types for each architecture"
  type        = map(list(string))
  default = {
    amd64 = ["t3.medium", "t3.large"]
    arm64 = ["t4g.medium", "t4g.large"]
  }
}

variable "namespace" {
  description = "Kubernetes namespace for Open Saves"
  type        = string
  default     = "open-saves"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
