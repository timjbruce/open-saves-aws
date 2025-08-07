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

# DocumentDB Subnet Group
resource "aws_docdb_subnet_group" "main" {
  name       = "open-saves-docdb-subnet-group"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name        = "open-saves-docdb-subnet-group"
    Environment = "production"
    Project     = "open-saves"
  }
}

# DocumentDB Security Group
resource "aws_security_group" "documentdb" {
  name        = "open-saves-documentdb-sg"
  description = "Security group for Open Saves DocumentDB"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [data.aws_ssm_parameter.cluster_security_group_id.value]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "open-saves-documentdb-sg"
    Environment = "production"
    Project     = "open-saves"
  }
}

# DocumentDB Cluster Parameter Group
resource "aws_docdb_cluster_parameter_group" "main" {
  family      = "docdb5.0"
  name        = "open-saves-docdb-params"
  description = "DocumentDB cluster parameter group for Open Saves"

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "ttl_monitor"
    value = "enabled"
  }

  tags = {
    Name        = "open-saves-docdb-params"
    Environment = "production"
    Project     = "open-saves"
  }
}

# Generate random password for DocumentDB
resource "random_password" "documentdb_password" {
  length  = 16
  special = true
}

# Store DocumentDB password in Secrets Manager
resource "aws_secretsmanager_secret" "documentdb_password" {
  name        = "open-saves-documentdb-password"
  description = "Password for Open Saves DocumentDB cluster"

  tags = {
    Name        = "open-saves-documentdb-password"
    Environment = "production"
    Project     = "open-saves"
  }
}

resource "aws_secretsmanager_secret_version" "documentdb_password" {
  secret_id     = aws_secretsmanager_secret.documentdb_password.id
  secret_string = random_password.documentdb_password.result
}

# DocumentDB Cluster
resource "aws_docdb_cluster" "main" {
  cluster_identifier      = "open-saves-docdb-cluster"
  engine                  = "docdb"
  engine_version          = "5.0.0"
  master_username         = "opensaves"
  master_password         = random_password.documentdb_password.result
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  skip_final_snapshot     = false
  final_snapshot_identifier = "open-saves-docdb-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  db_subnet_group_name            = aws_docdb_subnet_group.main.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.main.name
  vpc_security_group_ids          = [aws_security_group.documentdb.id]
  
  storage_encrypted = true
  kms_key_id       = aws_kms_key.documentdb.arn
  
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  
  deletion_protection = false

  tags = {
    Name        = "open-saves-docdb-cluster"
    Environment = "production"
    Project     = "open-saves"
  }
}

# KMS Key for DocumentDB encryption
resource "aws_kms_key" "documentdb" {
  description             = "KMS key for Open Saves DocumentDB encryption"
  deletion_window_in_days = 7

  tags = {
    Name        = "open-saves-documentdb-key"
    Environment = "production"
    Project     = "open-saves"
  }
}

resource "aws_kms_alias" "documentdb" {
  name          = "alias/open-saves-documentdb"
  target_key_id = aws_kms_key.documentdb.key_id
}

# DocumentDB Cluster Instances
resource "aws_docdb_cluster_instance" "cluster_instances" {
  count              = 2
  identifier         = "open-saves-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.architecture == "arm64" ? "db.t4g.medium" : "db.t3.medium"
  
  tags = {
    Name        = "open-saves-docdb-${count.index}"
    Environment = "production"
    Project     = "open-saves"
  }
}

# S3 Bucket for blob storage
resource "aws_s3_bucket" "blobs" {
  bucket = "open-saves-blobs-${data.aws_caller_identity.current.account_id}-${var.region}"

  tags = {
    Name        = "open-saves-blobs"
    Environment = "production"
    Project     = "open-saves"
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "blobs" {
  bucket                  = aws_s3_bucket.blobs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "open-saves-redis-subnet-group"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name        = "open-saves-redis-subnet-group"
    Environment = "production"
    Project     = "open-saves"
  }
}

# ElastiCache Security Group
resource "aws_security_group" "redis" {
  name        = "open-saves-redis-sg"
  description = "Security group for Open Saves Redis"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [data.aws_ssm_parameter.cluster_security_group_id.value]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "open-saves-redis-sg"
    Environment = "production"
    Project     = "open-saves"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "open-saves-redis"
  description                = "Redis cluster for Open Saves caching"
  
  node_type                  = var.architecture == "arm64" ? "cache.t4g.micro" : "cache.t3.micro"
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 2
  
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  tags = {
    Name        = "open-saves-redis"
    Environment = "production"
    Project     = "open-saves"
  }
}

# Store outputs in SSM Parameter Store for other steps
resource "aws_ssm_parameter" "documentdb_endpoint" {
  name  = "/open-saves/step2/documentdb_endpoint"
  type  = "String"
  value = aws_docdb_cluster.main.endpoint
}

resource "aws_ssm_parameter" "documentdb_port" {
  name  = "/open-saves/step2/documentdb_port"
  type  = "String"
  value = tostring(aws_docdb_cluster.main.port)
}

resource "aws_ssm_parameter" "documentdb_username" {
  name  = "/open-saves/step2/documentdb_username"
  type  = "String"
  value = aws_docdb_cluster.main.master_username
}

resource "aws_ssm_parameter" "documentdb_password_secret_arn" {
  name  = "/open-saves/step2/documentdb_password_secret_arn"
  type  = "String"
  value = aws_secretsmanager_secret.documentdb_password.arn
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/open-saves/step2/s3_bucket_name"
  type  = "String"
  value = aws_s3_bucket.blobs.bucket
}

resource "aws_ssm_parameter" "s3_bucket_id" {
  name  = "/open-saves/step2/s3_bucket_id"
  type  = "String"
  value = aws_s3_bucket.blobs.id
}

resource "aws_ssm_parameter" "s3_bucket_arn" {
  name  = "/open-saves/step2/s3_bucket_arn"
  type  = "String"
  value = aws_s3_bucket.blobs.arn
}

resource "aws_ssm_parameter" "redis_endpoint" {
  name  = "/open-saves/step2/redis_endpoint"
  type  = "String"
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

resource "aws_ssm_parameter" "redis_port" {
  name  = "/open-saves/step2/redis_port"
  type  = "String"
  value = tostring(aws_elasticache_replication_group.redis.port)
}
