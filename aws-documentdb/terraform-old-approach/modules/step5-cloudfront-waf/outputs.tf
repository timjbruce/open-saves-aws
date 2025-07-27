output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.open_saves_waf.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.open_saves_cdn.id
}

output "cloudfront_distribution_domain" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.open_saves_cdn.domain_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution (alias for compatibility)"
  value       = aws_cloudfront_distribution.open_saves_cdn.domain_name
}

output "cloudfront_to_elb_sg_id" {
  description = "ID of the security group for CloudFront to ELB traffic"
  value       = aws_security_group.cloudfront_to_elb.id
}

output "origin_verification_secret" {
  description = "Secret for origin verification"
  value       = random_password.origin_secret.result
  sensitive   = true
}
