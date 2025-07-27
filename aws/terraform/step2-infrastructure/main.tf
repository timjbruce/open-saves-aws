terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Get data from Step 1 via SSM Parameter Store
data "aws_ssm_parameter" "vpc_id" {
  name = "/open-saves/step1/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/open-saves/step1/private_subnet_ids"
}

data "aws_ssm_parameter" "cluster_security_group_id" {
  name = "/open-saves/step1/cluster_security_group_id"
}

data "aws_ssm_parameter" "ecr_repo_uri" {
  name = "/open-saves/step1/ecr_repo_uri"
}

data "aws_caller_identity" "current" {}

locals {
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
}

# DynamoDB Tables
resource "aws_dynamodb_table" "stores" {
  name         = "open-saves-stores"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "store_id"

  attribute {
    name = "store_id"
    type = "S"
  }

  tags = {
    Name        = "open-saves-stores"
    Environment = var.environment
    Project     = "open-saves"
  }
}

resource "aws_dynamodb_table" "records" {
  name         = "open-saves-records"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "store_id"
  range_key    = "record_id"

  attribute {
    name = "store_id"
    type = "S"
  }

  attribute {
    name = "record_id"
    type = "S"
  }

  attribute {
    name = "owner_id"
    type = "S"
  }

  attribute {
    name = "game_id"
    type = "S"
  }

  attribute {
    name = "concat_key"
    type = "S"
  }

  global_secondary_index {
    name            = "OwnerIDIndex"
    hash_key        = "owner_id"
    range_key       = "concat_key"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "GameIDIndex"
    hash_key        = "game_id"
    range_key       = "concat_key"
    projection_type = "ALL"
  }

  tags = {
    Name        = "open-saves-records"
    Environment = var.environment
    Project     = "open-saves"
  }
}

resource "aws_dynamodb_table" "metadata" {
  name         = "open-saves-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "metadata_type"
  range_key    = "metadata_id"

  attribute {
    name = "metadata_type"
    type = "S"
  }

  attribute {
    name = "metadata_id"
    type = "S"
  }

  tags = {
    Name        = "open-saves-metadata"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "blobs" {
  bucket        = "open-saves-blobs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "open-saves-blobs"
    Environment = var.environment
    Project     = "open-saves"
  }
}

resource "aws_s3_bucket_ownership_controls" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "blobs" {
  depends_on = [aws_s3_bucket_ownership_controls.blobs]
  bucket     = aws_s3_bucket.blobs.id
  acl        = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "blobs" {
  bucket                  = aws_s3_bucket.blobs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "open-saves-cache-subnet"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name        = "open-saves-cache-subnet"
    Environment = var.environment
    Project     = "open-saves"
  }
}

resource "aws_security_group" "redis" {
  name        = "open-saves-redis-sg"
  description = "Security group for Open Saves Redis"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.aws_ssm_parameter.cluster_security_group_id.value]
    description     = "Redis access from EKS cluster"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "open-saves-redis-sg"
    Environment = var.environment
    Project     = "open-saves"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "open-saves-cache"
  engine               = "redis"
  node_type            = "cache.t4g.small"  # Always use ARM64-based instance
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = {
    Name        = "open-saves-cache"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Store configuration in Parameter Store
resource "aws_ssm_parameter" "config" {
  name        = "/etc/open-saves/config.yaml"
  description = "Configuration for Open Saves"
  type        = "String"
  overwrite   = true
  value = jsonencode({
    server = {
      http_port = 8080
      grpc_port = 8081
    }
    aws = {
      region = var.region
      dynamodb = {
        stores_table   = aws_dynamodb_table.stores.name
        records_table  = aws_dynamodb_table.records.name
        metadata_table = aws_dynamodb_table.metadata.name
      }
      s3 = {
        bucket_name = aws_s3_bucket.blobs.bucket
      }
      elasticache = {
        address = "${aws_elasticache_cluster.redis.cache_nodes.0.address}:${aws_elasticache_cluster.redis.cache_nodes.0.port}"
        ttl     = 3600
      }
      ecr = {
        repository_uri = data.aws_ssm_parameter.ecr_repo_uri.value
      }
    }
  })

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

# Store outputs in SSM Parameter Store for other steps
resource "aws_ssm_parameter" "dynamodb_table_arns" {
  name  = "/open-saves/step2/dynamodb_table_arns"
  type  = "StringList"
  value = join(",", [
    aws_dynamodb_table.stores.arn,
    aws_dynamodb_table.records.arn,
    aws_dynamodb_table.metadata.arn,
    "${aws_dynamodb_table.records.arn}/index/GameIDIndex",
    "${aws_dynamodb_table.records.arn}/index/OwnerIDIndex"
  ])

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "dynamodb_table_names" {
  name  = "/open-saves/step2/dynamodb_table_names"
  type  = "StringList"
  value = join(",", [
    aws_dynamodb_table.stores.name,
    aws_dynamodb_table.records.name,
    aws_dynamodb_table.metadata.name
  ])

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "s3_bucket_arn" {
  name  = "/open-saves/step2/s3_bucket_arn"
  type  = "String"
  value = aws_s3_bucket.blobs.arn

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "s3_bucket_id" {
  name  = "/open-saves/step2/s3_bucket_id"
  type  = "String"
  value = aws_s3_bucket.blobs.id

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/open-saves/step2/s3_bucket_name"
  type  = "String"
  value = aws_s3_bucket.blobs.bucket

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "redis_endpoint" {
  name  = "/open-saves/step2/redis_endpoint"
  type  = "String"
  value = "${aws_elasticache_cluster.redis.cache_nodes.0.address}:${aws_elasticache_cluster.redis.cache_nodes.0.port}"

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}

resource "aws_ssm_parameter" "parameter_store_name" {
  name  = "/open-saves/step2/parameter_store_name"
  type  = "String"
  value = "/etc/open-saves/config.yaml"

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step2"
  }
}
