output "documentdb_cluster_endpoint" {
  description = "DocumentDB cluster endpoint"
  value       = aws_docdb_cluster.main.endpoint
}

output "documentdb_cluster_port" {
  description = "DocumentDB cluster port"
  value       = aws_docdb_cluster.main.port
}

output "documentdb_cluster_master_username" {
  description = "DocumentDB cluster master username"
  value       = aws_docdb_cluster.main.master_username
}

output "documentdb_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DocumentDB password"
  value       = aws_secretsmanager_secret.documentdb_password.arn
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.blobs.arn
}

output "s3_bucket_id" {
  description = "ID of the S3 bucket"
  value       = aws_s3_bucket.blobs.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.blobs.bucket
}

output "redis_endpoint" {
  description = "Redis cluster primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_replication_group.redis.port
}
