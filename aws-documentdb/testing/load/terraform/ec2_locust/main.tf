provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Data source for Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local values
locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2.id
}

# VPC for Locust
resource "aws_vpc" "locust_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "open-saves-locust-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "locust_igw" {
  vpc_id = aws_vpc.locust_vpc.id

  tags = {
    Name = "open-saves-locust-igw"
  }
}

# Public Subnets
resource "aws_subnet" "locust_public_subnet_1" {
  vpc_id                  = aws_vpc.locust_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "open-saves-locust-public-subnet-1"
  }
}

resource "aws_subnet" "locust_public_subnet_2" {
  vpc_id                  = aws_vpc.locust_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "open-saves-locust-public-subnet-2"
  }
}

# Route Table
resource "aws_route_table" "locust_public_rt" {
  vpc_id = aws_vpc.locust_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.locust_igw.id
  }

  tags = {
    Name = "open-saves-locust-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "locust_public_rta_1" {
  subnet_id      = aws_subnet.locust_public_subnet_1.id
  route_table_id = aws_route_table.locust_public_rt.id
}

resource "aws_route_table_association" "locust_public_rta_2" {
  subnet_id      = aws_subnet.locust_public_subnet_2.id
  route_table_id = aws_route_table.locust_public_rt.id
}

# Security Group for Locust
resource "aws_security_group" "locust" {
  name        = "open-saves-locust-sg"
  description = "Security group for Locust master and workers"
  vpc_id      = aws_vpc.locust_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "SSH access"
  }

  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "Locust web interface"
  }

  ingress {
    from_port   = 5557
    to_port     = 5558
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
    description = "Locust worker communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-saves-locust-sg"
  }
}

# IAM role for Locust instances
resource "aws_iam_role" "locust_role" {
  name = "open-saves-locust-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Locust instances
resource "aws_iam_role_policy" "locust_policy" {
  name = "open-saves-locust-policy"
  role = aws_iam_role.locust_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::${var.scripts_bucket}",
          "arn:aws:s3:::${var.scripts_bucket}/*"
        ]
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile for Locust instances
resource "aws_iam_instance_profile" "locust_profile" {
  name = "open-saves-locust-profile"
  role = aws_iam_role.locust_role.name
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "open_saves_eks" {
  dashboard_name = "OpenSavesEKSEnvironment"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Open Saves EKS Environment Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "pod_cpu_utilization_over_pod_limit", "ClusterName", "open-saves-cluster", "Namespace", "default"],
            ["AWS/EKS", "pod_cpu_utilization", "ClusterName", "open-saves-cluster", "Namespace", "default"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "EKS - Pod CPU Utilization"
          period  = 60
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "pod_memory_utilization_over_pod_limit", "ClusterName", "open-saves-cluster", "Namespace", "default"],
            ["AWS/EKS", "pod_memory_utilization", "ClusterName", "open-saves-cluster", "Namespace", "default"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "EKS - Pod Memory Utilization"
          period  = 60
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", "ClusterName", "open-saves-cluster"],
            ["AWS/EKS", "cluster_node_count", "ClusterName", "open-saves-cluster"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "EKS - Cluster Node Status"
          period  = 60
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "pod_network_rx_bytes", "ClusterName", "open-saves-cluster", "Namespace", "default"],
            ["AWS/EKS", "pod_network_tx_bytes", "ClusterName", "open-saves-cluster", "Namespace", "default"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "EKS - Pod Network Traffic"
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "open-saves-stores"],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "open-saves-records"],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "open-saves-metadata"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "DynamoDB - Read Capacity Units"
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "open-saves-stores"],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "open-saves-records"],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "open-saves-metadata"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "DynamoDB - Write Capacity Units"
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "GetRequests", "BucketName", "open-saves-blobs"],
            ["AWS/S3", "PutRequests", "BucketName", "open-saves-blobs"],
            ["AWS/S3", "DeleteRequests", "BucketName", "open-saves-blobs"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 - Request Count"
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 19
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "open-saves-redis"],
            ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", "open-saves-redis"],
            ["AWS/ElastiCache", "CacheHitRate", "CacheClusterId", "open-saves-redis"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "ElastiCache - Performance"
          period  = 60
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 25
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", "${var.cloudfront_distribution_id}", "Region", "Global"],
            ["AWS/CloudFront", "TotalErrorRate", "DistributionId", "${var.cloudfront_distribution_id}", "Region", "Global"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "CloudFront - Requests and Error Rate"
          period  = 60
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 25
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", "${var.cloudfront_distribution_id}", "Region", "Global"],
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", "${var.cloudfront_distribution_id}", "Region", "Global"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "CloudFront - Error Rates by Type"
          period  = 60
          stat    = "Average"
        }
      }
    ]
  })
}

# CloudWatch log group for Locust
resource "aws_cloudwatch_log_group" "locust" {
  name              = "/ec2/open-saves-locust"
  retention_in_days = 7
}

# Locust master instance
resource "aws_instance" "locust_master" {
  ami                    = local.ami_id
  instance_type          = var.locust_instance_type
  vpc_security_group_ids = [aws_security_group.locust.id]
  subnet_id              = aws_subnet.locust_public_subnet_1.id
  iam_instance_profile   = aws_iam_instance_profile.locust_profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install required packages
    yum update -y
    yum install -y python3 python3-pip git

    # Downgrade urllib3 to avoid OpenSSL compatibility issues
    pip3 install urllib3==1.26.15

    # Install Locust
    pip3 install locust

    # Create directory for Locust files
    mkdir -p /opt/locust

    # Copy locustfile from S3
    aws s3 cp s3://${var.scripts_bucket}/locustfile.py /opt/locust/locustfile.py

    # Ensure endpoint has http:// or https:// prefix
    ENDPOINT="${var.open_saves_endpoint}"
    if [[ ! "$${ENDPOINT}" =~ ^https?:// ]]; then
      ENDPOINT="https://$${ENDPOINT}"
    fi

    # Start Locust master
    cd /opt/locust
    nohup locust -f locustfile.py --master --host=$${ENDPOINT} --web-host=0.0.0.0 > /var/log/locust-master.log 2>&1 &

    # Wait for Locust to start
    sleep 5

    # Print the Locust master URL
    echo "Locust master is running at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8089"
  EOF

  tags = {
    Name = "open-saves-locust-master"
  }
}

# Locust worker instances
resource "aws_instance" "locust_worker" {
  count                  = var.worker_count
  ami                    = local.ami_id
  instance_type          = var.locust_instance_type
  vpc_security_group_ids = [aws_security_group.locust.id]
  subnet_id              = count.index % 2 == 0 ? aws_subnet.locust_public_subnet_1.id : aws_subnet.locust_public_subnet_2.id
  iam_instance_profile   = aws_iam_instance_profile.locust_profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install required packages
    yum update -y
    yum install -y python3 python3-pip git

    # Downgrade urllib3 to avoid OpenSSL compatibility issues
    pip3 install urllib3==1.26.15

    # Install Locust
    pip3 install locust

    # Create directory for Locust files
    mkdir -p /opt/locust

    # Copy locustfile from S3
    aws s3 cp s3://${var.scripts_bucket}/locustfile.py /opt/locust/locustfile.py

    # Ensure endpoint has http:// or https:// prefix
    ENDPOINT="${var.open_saves_endpoint}"
    if [[ ! "$${ENDPOINT}" =~ ^https?:// ]]; then
      ENDPOINT="https://$${ENDPOINT}"
    fi

    # Start Locust worker
    cd /opt/locust
    nohup locust -f locustfile.py --worker --master-host=${aws_instance.locust_master.private_ip} --host=$${ENDPOINT} > /var/log/locust-worker.log 2>&1 &

    # Print confirmation
    echo "Locust worker started and connected to master at ${aws_instance.locust_master.private_ip}"
  EOF

  tags = {
    Name = "open-saves-locust-worker-${count.index + 1}"
  }

  depends_on = [aws_instance.locust_master]
}

# Output the Locust master URL
output "locust_web_ui" {
  value = "http://${aws_instance.locust_master.public_ip}:8089"
  description = "URL for the Locust web UI"
}

# Output the CloudWatch dashboard URL
output "cloudwatch_dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.open_saves_eks.dashboard_name}"
  description = "URL for the CloudWatch dashboard"
}
