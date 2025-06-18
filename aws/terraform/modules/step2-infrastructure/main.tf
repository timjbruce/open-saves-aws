provider "aws" {
  region = var.region
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
}

# S3 Bucket
resource "aws_s3_bucket" "blobs" {
  bucket = "open-saves-blobs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "blobs" {
  depends_on = [aws_s3_bucket_ownership_controls.blobs]
  bucket = aws_s3_bucket.blobs.id
  acl    = "private"
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "open-saves-cache-subnet"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name        = "open-saves-redis-sg"
  description = "Security group for Open Saves Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "open-saves-cache"
  engine               = "redis"
  node_type            = var.architecture == "arm64" ? "cache.t4g.small" : "cache.t3.small"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
}

# Create config in Parameter Store
resource "aws_ssm_parameter" "config" {
  name        = "/etc/open-saves/config.yaml"
  description = "Configuration for Open Saves"
  type        = "String"
  overwrite   = true
  value       = jsonencode({
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
        repository_uri = var.ecr_repo_uri
      }
    }
  })
}

# Create config.yaml file for backward compatibility
resource "local_file" "config_yaml" {
  content = <<-EOT
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "${var.region}"
  dynamodb:
    stores_table: "${aws_dynamodb_table.stores.name}"
    records_table: "${aws_dynamodb_table.records.name}"
    metadata_table: "${aws_dynamodb_table.metadata.name}"
  s3:
    bucket_name: "${aws_s3_bucket.blobs.bucket}"
  elasticache:
    address: "${aws_elasticache_cluster.redis.cache_nodes.0.address}:${aws_elasticache_cluster.redis.cache_nodes.0.port}"
    ttl: 3600
  ecr:
    repository_uri: "${var.ecr_repo_uri}"
EOT
  filename = "${var.config_path}/config.yaml"
}

data "aws_caller_identity" "current" {}
