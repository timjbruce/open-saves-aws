/**
 * CloudWatch resources for Open Saves load testing observability
 */

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "redis_cache_cluster_id" {
  description = "ID of the ElastiCache Redis cluster"
  type        = string
}

# Enable Container Insights on the EKS cluster
resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${var.eks_cluster_name}/performance"
  retention_in_days = 7
}

# Create CloudWatch dashboards
resource "aws_cloudwatch_dashboard" "eks_dashboard" {
  dashboard_name = "OpenSaves-EKS-${var.environment}"
  
  dashboard_body = templatefile("${path.module}/../dashboards/eks_dashboard.json", {
    Region      = var.region
    ClusterName = var.eks_cluster_name
  })
}

resource "aws_cloudwatch_dashboard" "dynamodb_dashboard" {
  dashboard_name = "OpenSaves-DynamoDB-${var.environment}"
  
  dashboard_body = templatefile("${path.module}/../dashboards/dynamodb_dashboard.json", {
    Region = var.region
  })
}

resource "aws_cloudwatch_dashboard" "s3_dashboard" {
  dashboard_name = "OpenSaves-S3-${var.environment}"
  
  dashboard_body = templatefile("${path.module}/../dashboards/s3_dashboard.json", {
    Region     = var.region
    BucketName = var.s3_bucket_name
  })
}

resource "aws_cloudwatch_dashboard" "redis_dashboard" {
  dashboard_name = "OpenSaves-Redis-${var.environment}"
  
  dashboard_body = templatefile("${path.module}/../dashboards/redis_dashboard.json", {
    Region        = var.region
    CacheClusterId = var.redis_cache_cluster_id
  })
}

# Create CloudWatch alarms for critical metrics
resource "aws_cloudwatch_metric_alarm" "eks_cpu_high" {
  alarm_name          = "open-saves-eks-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This alarm monitors EKS pod CPU utilization"
  
  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = "open-saves"
  }
  
  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "open-saves-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This alarm monitors DynamoDB throttled requests"
  
  dimensions = {
    TableName = "open-saves-records"
  }
  
  alarm_actions = []
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "open-saves-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This alarm monitors Redis CPU utilization"
  
  dimensions = {
    CacheClusterId = var.redis_cache_cluster_id
  }
  
  alarm_actions = []
}

# Output the dashboard URLs
output "eks_dashboard_url" {
  description = "URL for the EKS dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.eks_dashboard.dashboard_name}"
}

output "dynamodb_dashboard_url" {
  description = "URL for the DynamoDB dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.dynamodb_dashboard.dashboard_name}"
}

output "s3_dashboard_url" {
  description = "URL for the S3 dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.s3_dashboard.dashboard_name}"
}

output "redis_dashboard_url" {
  description = "URL for the Redis dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.redis_dashboard.dashboard_name}"
}
