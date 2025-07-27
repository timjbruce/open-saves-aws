output "dynamodb_table_arns" {
  description = "ARNs of the DynamoDB tables including GSI ARNs"
  value = [
    aws_dynamodb_table.stores.arn,
    aws_dynamodb_table.records.arn,
    aws_dynamodb_table.metadata.arn,
    "${aws_dynamodb_table.records.arn}/index/GameIDIndex",
    "${aws_dynamodb_table.records.arn}/index/OwnerIDIndex"
  ]
}

output "dynamodb_table_names" {
  description = "Names of the DynamoDB tables"
  value = [
    aws_dynamodb_table.stores.name,
    aws_dynamodb_table.records.name,
    aws_dynamodb_table.metadata.name
  ]
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
  description = "Redis cluster endpoint"
  value       = "${aws_elasticache_cluster.redis.cache_nodes.0.address}:${aws_elasticache_cluster.redis.cache_nodes.0.port}"
}

output "parameter_store_name" {
  description = "Name of the parameter store configuration"
  value       = aws_ssm_parameter.config.name
}
