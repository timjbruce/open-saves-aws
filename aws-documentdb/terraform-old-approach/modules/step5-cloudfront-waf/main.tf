provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# WAF Web ACL for DDoS Protection
resource "aws_wafv2_web_acl" "open_saves_waf" {
  name        = "open-saves-waf-${var.architecture}"
  description = "WAF for Open Saves API protection"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rate-based rule to limit requests from any single IP
  rule {
    name     = "rate-limit-rule"
    priority = 1

    action {
      block {}
    }

    #this is set high for loadtesting only
    statement {
      rate_based_statement {
        limit              = 10000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # SQL Injection Protection
  rule {
    name     = "sql-injection-rule"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "OpenSavesWAF-${var.architecture}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "open-saves-waf-${var.architecture}"
  }
}

# Log configuration for WAF
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "/aws/waf/open-saves-${var.architecture}"
  retention_in_days = 30
}

# WAF logging will be configured manually after deployment
# resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
#   log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
#   resource_arn            = aws_wafv2_web_acl.open_saves_waf.arn
# }

# Create a CloudFront WAF for the distribution
resource "aws_wafv2_web_acl" "cloudfront_waf" {
  provider    = aws.us-east-1  # CloudFront requires WAF in us-east-1
  name        = "open-saves-cloudfront-waf-${var.architecture}"
  description = "WAF for Open Saves CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate-based rule to limit requests from any single IP
  rule {
    name     = "cf-rate-limit-rule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CFRateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules for common threats
  rule {
    name     = "cf-aws-managed-rules"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CFAWSManagedRules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "OpenSavesCloudfrontWAF-${var.architecture}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "open-saves-cloudfront-waf-${var.architecture}"
  }
}

# Create a security group for CloudFront to ELB communication
resource "aws_security_group" "cloudfront_to_elb" {
  name        = "cloudfront-to-elb-${var.architecture}"
  description = "Allow traffic from CloudFront to ELB"
  vpc_id      = var.vpc_id

  # We'll add rules after CloudFront distribution is created
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-saves-cloudfront-to-elb-${var.architecture}"
  }
}

# Create an origin access identity for CloudFront
resource "aws_cloudfront_origin_access_identity" "open_saves_oai" {
  comment = "OAI for Open Saves CloudFront distribution ${var.architecture}"
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "open_saves_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Open Saves CDN ${var.architecture}"
  default_root_object = ""
  price_class         = "PriceClass_100"  # Use only North America and Europe edge locations
  wait_for_deployment = false

  # Origin configuration for the ELB
  origin {
    domain_name = var.load_balancer_dns
    origin_id   = "ELB-open-saves-${var.architecture}"
    
    custom_origin_config {
      http_port              = 8080
      https_port             = 8081
      origin_protocol_policy = "http-only"  # Change to https-only if you configure SSL on your ELB
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_keepalive_timeout = 60
      origin_read_timeout = 60
    }
    
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_secret.result
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "ELB-open-saves-${var.architecture}"
    
    forwarded_values {
      query_string = true
      headers      = ["*"]
      
      cookies {
        forward = "all"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }
  
  # Associate CloudFront WAF
  web_acl_id = aws_wafv2_web_acl.cloudfront_waf.arn

  # Restrict viewer access
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL certificate
  viewer_certificate {
    cloudfront_default_certificate = true
    # Use the following if you have a custom certificate
    # acm_certificate_arn = var.acm_certificate_arn
    # ssl_support_method = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "open-saves-cdn"
  }
}

# Generate a random secret for origin verification
resource "random_password" "origin_secret" {
  length  = 32
  special = false
}

# Use predefined CloudFront IP ranges instead of dynamically adding them
# This avoids hitting the security group rule limit
# These are the main CloudFront IP ranges consolidated into larger CIDR blocks
resource "aws_security_group_rule" "cloudfront_to_elb_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [
    "120.52.22.96/27",
    "205.251.249.0/24",
    "180.163.57.0/24",
    "204.246.168.0/22",
    "111.13.171.0/24",
    "18.160.0.0/15",
    "205.251.252.0/23",
    "54.192.0.0/16",
    "204.246.173.0/24",
    "54.230.200.0/21",
    "120.253.240.0/24",
    "116.129.226.0/24",
    "130.176.0.0/16",
    "3.160.0.0/12",
    "108.156.0.0/14",
    "99.86.0.0/16",
    "13.32.0.0/12",
    "70.132.0.0/18",
    "13.224.0.0/12",
    "205.251.208.0/20"
  ]
  security_group_id = aws_security_group.cloudfront_to_elb.id
  description       = "Allow CloudFront IPs to access port 8080"
}

resource "aws_security_group_rule" "cloudfront_to_elb_8081" {
  type              = "ingress"
  from_port         = 8081
  to_port           = 8081
  protocol          = "tcp"
  cidr_blocks       = [
    "120.52.22.96/27",
    "205.251.249.0/24",
    "180.163.57.0/24",
    "204.246.168.0/22",
    "111.13.171.0/24",
    "18.160.0.0/15",
    "205.251.252.0/23",
    "54.192.0.0/16",
    "204.246.173.0/24",
    "54.230.200.0/21",
    "120.253.240.0/24",
    "116.129.226.0/24",
    "130.176.0.0/16",
    "3.160.0.0/12",
    "108.156.0.0/14",
    "99.86.0.0/16",
    "13.32.0.0/12",
    "70.132.0.0/18",
    "13.224.0.0/12",
    "205.251.208.0/20"
  ]
  security_group_id = aws_security_group.cloudfront_to_elb.id
  description       = "Allow CloudFront IPs to access port 8081"
}

# Create a CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "open_saves_security" {
  dashboard_name = "OpenSaves-Security"
  
  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/WAFV2", "BlockedRequests", "WebACL", "${aws_wafv2_web_acl.open_saves_waf.name}", "Region", "${var.region}" ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${var.region}",
        "title": "WAF Blocked Requests"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/WAFV2", "CountedRequests", "WebACL", "${aws_wafv2_web_acl.open_saves_waf.name}", "Region", "${var.region}" ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${var.region}",
        "title": "WAF Counted Requests"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/CloudFront", "Requests", "DistributionId", "${aws_cloudfront_distribution.open_saves_cdn.id}" ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "CloudFront Requests"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/CloudFront", "4xxErrorRate", "DistributionId", "${aws_cloudfront_distribution.open_saves_cdn.id}" ],
          [ ".", "5xxErrorRate", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "CloudFront Error Rates"
      }
    }
  ]
}
EOF
}
