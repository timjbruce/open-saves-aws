provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Create S3 bucket for Locust scripts
resource "aws_s3_bucket" "locust_scripts" {
  bucket = "open-saves-locust-scripts-${var.environment}"

  tags = {
    Name        = "open-saves-locust-scripts"
    Environment = var.environment
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "locust_scripts" {
  bucket = aws_s3_bucket.locust_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption for the bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "locust_scripts" {
  bucket = aws_s3_bucket.locust_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Create bucket policy to allow access from any role in the account
resource "aws_s3_bucket_policy" "locust_scripts" {
  bucket = aws_s3_bucket.locust_scripts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.locust_scripts.arn,
          "${aws_s3_bucket.locust_scripts.arn}/*"
        ]
      }
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Output the bucket name
output "bucket_name" {
  value = aws_s3_bucket.locust_scripts.bucket
  description = "Name of the S3 bucket for Locust scripts"
}

# Output the bucket ARN
output "bucket_arn" {
  value = aws_s3_bucket.locust_scripts.arn
  description = "ARN of the S3 bucket for Locust scripts"
}
