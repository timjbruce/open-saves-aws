output "dynamodb_table_arns" {
  description = "ARNs of the DynamoDB tables"
  value       = [
    aws_dynamodb_table.stores.arn,
    aws_dynamodb_table.records.arn,
    aws_dynamodb_table.metadata.arn
  ]
}

output "dynamodb_table_names" {
  description = "Names of the DynamoDB tables"
  value       = {
    stores   = aws_dynamodb_table.stores.name
    records  = aws_dynamodb_table.records.name
    metadata = aws_dynamodb_table.metadata.name
  }
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.blobs.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.blobs.bucket
}

output "redis_endpoint" {
  description = "Endpoint of the ElastiCache Redis cluster"
  value       = "${aws_elasticache_cluster.redis.cache_nodes.0.address}:${aws_elasticache_cluster.redis.cache_nodes.0.port}"
}

output "redis_security_group_id" {
  description = "ID of the Redis security group"
  value       = aws_security_group.redis.id
}

output "parameter_store_name" {
  description = "Name of the Parameter Store parameter containing the configuration"
  value       = aws_ssm_parameter.config.name
}
