/**
 * Locust load testing infrastructure for Open Saves
 */

variable "vpc_id" {
  description = "VPC ID where the load testing infrastructure will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs where the load testing infrastructure will be deployed"
  type        = list(string)
}

variable "open_saves_url" {
  description = "URL of the Open Saves API (CloudFront or Load Balancer)"
  type        = string
}

variable "locust_instance_type" {
  description = "EC2 instance type for the Locust master"
  type        = string
  default     = "t3.medium"
}

variable "locust_workers_count" {
  description = "Number of Locust worker tasks to run"
  type        = number
  default     = 5
}

# Security group for Locust master
resource "aws_security_group" "locust_master" {
  name        = "open-saves-locust-master"
  description = "Security group for Locust master"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Locust web interface"
  }

  ingress {
    from_port   = 5557
    to_port     = 5557
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Locust worker communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-saves-locust-master"
  }
}

# IAM role for Locust EC2 instance
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

resource "aws_iam_role_policy" "locust_policy" {
  name = "open-saves-locust-policy"
  role = aws_iam_role.locust_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeInstances"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "locust_profile" {
  name = "open-saves-locust-profile"
  role = aws_iam_role.locust_role.name
}

# Locust master EC2 instance
resource "aws_instance" "locust_master" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.locust_instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.locust_master.id]
  iam_instance_profile   = aws_iam_instance_profile.locust_profile.name
  key_name               = var.key_name

  user_data = templatefile("${path.module}/user_data/locust_master.sh", {
    open_saves_url = var.open_saves_url
  })

  tags = {
    Name = "open-saves-locust-master"
  }
}

# Latest Amazon Linux 2 AMI
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

# ECS cluster for Locust workers
resource "aws_ecs_cluster" "locust_workers" {
  name = "open-saves-locust-workers"
}

# Task definition for Locust workers
resource "aws_ecs_task_definition" "locust_worker" {
  family                   = "open-saves-locust-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.locust_execution_role.arn
  task_role_arn            = aws_iam_role.locust_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "locust-worker"
      image     = "locustio/locust:latest"
      essential = true
      command   = ["--worker", "--master-host", aws_instance.locust_master.private_ip]
      environment = [
        {
          name  = "LOCUST_HOST",
          value = var.open_saves_url
        },
        {
          name  = "LOCUST_LOCUSTFILE",
          value = "/locust/locustfile.py"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "locust-scripts"
          containerPath = "/locust"
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.locust_workers.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "locust-worker"
        }
      }
    }
  ])

  volume {
    name = "locust-scripts"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.locust_scripts.id
      root_directory = "/"
    }
  }
}

# IAM roles for ECS
resource "aws_iam_role" "locust_execution_role" {
  name = "open-saves-locust-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "locust_execution_policy" {
  role       = aws_iam_role.locust_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "locust_task_role" {
  name = "open-saves-locust-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# CloudWatch log group for Locust workers
resource "aws_cloudwatch_log_group" "locust_workers" {
  name              = "/ecs/open-saves-locust-workers"
  retention_in_days = 7
}

# EFS file system for sharing Locust scripts
resource "aws_efs_file_system" "locust_scripts" {
  creation_token = "open-saves-locust-scripts"

  tags = {
    Name = "open-saves-locust-scripts"
  }
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name        = "open-saves-locust-efs"
  description = "Security group for Locust EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.locust_master.id]
    description     = "NFS from Locust master"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-saves-locust-efs"
  }
}

# EFS mount targets
resource "aws_efs_mount_target" "locust_scripts" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.locust_scripts.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Locust worker service
resource "aws_ecs_service" "locust_workers" {
  name            = "open-saves-locust-workers"
  cluster         = aws_ecs_cluster.locust_workers.id
  task_definition = aws_ecs_task_definition.locust_worker.arn
  desired_count   = var.locust_workers_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [aws_security_group.locust_workers.id]
  }

  depends_on = [aws_efs_mount_target.locust_scripts]
}

# Security group for Locust workers
resource "aws_security_group" "locust_workers" {
  name        = "open-saves-locust-workers"
  description = "Security group for Locust workers"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-saves-locust-workers"
  }
}

# Output the Locust web UI URL
output "locust_ui_url" {
  description = "URL for the Locust web UI"
  value       = "http://${aws_instance.locust_master.public_ip}:8089"
}
