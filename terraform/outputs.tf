output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.step1_cluster_ecr.cluster_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.step1_cluster_ecr.ecr_repo_uri
}

output "dynamodb_table_names" {
  description = "Names of the DynamoDB tables"
  value       = module.step2_infrastructure.dynamodb_table_names
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = module.step2_infrastructure.s3_bucket_name
}

output "redis_endpoint" {
  description = "Endpoint of the ElastiCache Redis cluster"
  value       = module.step2_infrastructure.redis_endpoint
}

output "load_balancer_hostname" {
  description = "Hostname of the load balancer"
  value       = module.step4_compute_app.load_balancer_hostname
}
