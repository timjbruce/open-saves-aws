variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "open_saves_endpoint" {
  description = "Target endpoint URL for load testing"
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for Open Saves"
  type        = string
  default     = "EV2NR6DUG279M"  # Default ID for the Open Saves CloudFront distribution
}

variable "locust_instance_type" {
  description = "EC2 instance type for Locust master and workers"
  type        = string
  default     = "c5.large"
}

variable "worker_count" {
  description = "Number of Locust worker instances"
  type        = number
  default     = 3
}

variable "ami_id" {
  description = "AMI ID for Locust instances"
  type        = string
  default     = "" # Will be populated by data source if empty
}

variable "scripts_bucket" {
  description = "S3 bucket name containing Locust scripts"
  type        = string
}

variable "allowed_ip" {
  description = "IP address allowed to access the Locust web interface and SSH (in CIDR notation)"
  type        = string
  default     = "0.0.0.0/0"  # Default to allow all, but should be restricted in production
}
