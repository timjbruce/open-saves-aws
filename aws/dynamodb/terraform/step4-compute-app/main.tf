terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Get data from previous steps via SSM Parameter Store
data "aws_ssm_parameter" "cluster_name" {
  name = "/open-saves/step1/cluster_name"
}

data "aws_ssm_parameter" "cluster_endpoint" {
  name = "/open-saves/step1/cluster_endpoint"
}

data "aws_ssm_parameter" "cluster_certificate_authority_data" {
  name = "/open-saves/step1/cluster_certificate_authority_data"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/open-saves/step1/private_subnet_ids"
}

data "aws_ssm_parameter" "oidc_provider" {
  name = "/open-saves/step1/oidc_provider"
}

data "aws_ssm_parameter" "oidc_provider_arn" {
  name = "/open-saves/step1/oidc_provider_arn"
}

data "aws_ssm_parameter" "ecr_repo_uri" {
  name = "/open-saves/step1/ecr_repo_uri"
}

data "aws_ssm_parameter" "dynamodb_table_arns" {
  name = "/open-saves/step2/dynamodb_table_arns"
}

data "aws_ssm_parameter" "dynamodb_table_names" {
  name = "/open-saves/step2/dynamodb_table_names"
}

data "aws_ssm_parameter" "s3_bucket_arn" {
  name = "/open-saves/step2/s3_bucket_arn"
}

data "aws_ssm_parameter" "s3_bucket_id" {
  name = "/open-saves/step2/s3_bucket_id"
}

data "aws_ssm_parameter" "s3_bucket_name" {
  name = "/open-saves/step2/s3_bucket_name"
}

data "aws_ssm_parameter" "redis_endpoint" {
  name = "/open-saves/step2/redis_endpoint"
}

data "aws_ssm_parameter" "container_image_uri" {
  name = "/open-saves/step3/container_image_uri_${var.architecture}"
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name         = data.aws_ssm_parameter.cluster_name.value
  private_subnet_ids   = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  dynamodb_table_arns  = split(",", data.aws_ssm_parameter.dynamodb_table_arns.value)
  dynamodb_table_names = split(",", data.aws_ssm_parameter.dynamodb_table_names.value)
}

provider "kubernetes" {
  host                   = data.aws_ssm_parameter.cluster_endpoint.value
  cluster_ca_certificate = base64decode(data.aws_ssm_parameter.cluster_certificate_authority_data.value)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    command     = "aws"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "nodes" {
  cluster_name    = local.cluster_name
  node_group_name = "${var.architecture}-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = local.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = var.instance_types[var.architecture]
  
  # Use the appropriate AMI based on architecture
  ami_type = var.architecture == "arm64" ? "AL2_ARM_64" : "AL2_x86_64"

  tags = {
    Name        = "${var.architecture}-nodes"
    Environment = var.environment
    Project     = "open-saves"
  }

  # Required for the nodes to join the cluster
  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# IAM Role for Node Group
resource "aws_iam_role" "node_role" {
  name = "open-saves-${var.architecture}-node-role"

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

  tags = {
    Name        = "open-saves-${var.architecture}-node-role"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# IAM Policies for Node Group
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

# Add SSM Parameter Store read access for nodes
resource "aws_iam_role_policy" "node_ssm_policy" {
  name = "open-saves-ssm-policy-${var.architecture}"
  role = aws_iam_role.node_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/open-saves/*",
          "arn:aws:ssm:${var.region}:*:parameter/etc/open-saves/*"
        ]
      }
    ]
  })
}

# IAM Role for Service Account
resource "aws_iam_role" "service_account_role" {
  name = "open-saves-sa-role-${var.architecture}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_ssm_parameter.oidc_provider_arn.value
        }
        Condition = {
          StringEquals = {
            "${data.aws_ssm_parameter.oidc_provider.value}:sub" = "system:serviceaccount:${var.namespace}:open-saves-sa"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "open-saves-sa-role-${var.architecture}"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# IAM Policies for Service Account - DynamoDB
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "open-saves-dynamodb-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Stores Table permissions
        # Used in: CreateStore, GetStore, ListStores, DeleteStore
        Action = [
          "dynamodb:PutItem",    # CreateStore
          "dynamodb:GetItem",    # GetStore
          "dynamodb:Scan",       # ListStores
          "dynamodb:DeleteItem"  # DeleteStore
        ]
        Effect   = "Allow"
        Resource = local.dynamodb_table_arns[0] # Stores table ARN
      },
      {
        # Records Table permissions (including GSI access)
        # Used in: CreateRecord, GetRecord, QueryRecords, UpdateRecord, DeleteRecord, DeleteStore (batch operations)
        Action = [
          "dynamodb:PutItem",        # CreateRecord
          "dynamodb:GetItem",        # GetRecord
          "dynamodb:Query",          # QueryRecords (main table and GSIs), DeleteStore (to find records)
          "dynamodb:UpdateItem",     # UpdateRecord
          "dynamodb:DeleteItem",     # DeleteRecord
          "dynamodb:BatchWriteItem"  # DeleteStore (batch delete records)
        ]
        Effect   = "Allow"
        Resource = [
          local.dynamodb_table_arns[1],                                    # Records table ARN
          "${local.dynamodb_table_arns[1]}/index/GameIDIndex",            # GameID GSI for game-based queries
          "${local.dynamodb_table_arns[1]}/index/OwnerIDIndex"            # OwnerID GSI for owner-based queries
        ]
      },
      {
        # Metadata Table permissions
        # Used in: CreateStore, CreateRecord, DeleteRecord, SetMetadata, GetMetadata, QueryMetadata, DeleteStore, DeleteMetadata
        Action = [
          "dynamodb:PutItem",    # CreateStore, CreateRecord, DeleteRecord, SetMetadata
          "dynamodb:GetItem",    # CreateRecord, DeleteRecord, GetMetadata
          "dynamodb:DeleteItem", # DeleteStore, DeleteMetadata
          "dynamodb:Query"       # QueryMetadata
        ]
        Effect   = "Allow"
        Resource = local.dynamodb_table_arns[2] # Metadata table ARN
      }
    ]
  })
}

# IAM Policies for Service Account - S3
resource "aws_iam_role_policy" "s3_policy" {
  name = "open-saves-s3-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # S3 Blob Storage permissions
        # Used for: blob upload, download, deletion, and listing operations
        Action = [
          "s3:HeadObject",      # Check if blob exists
          "s3:GetObject",       # Download blob content
          "s3:PutObject",       # Upload blob content
          "s3:DeleteObject",    # Delete blob
          "s3:ListObjectsV2"    # List blobs for a record
        ]
        Effect   = "Allow"
        Resource = [
          data.aws_ssm_parameter.s3_bucket_arn.value,      # Bucket-level permissions for ListObjectsV2
          "${data.aws_ssm_parameter.s3_bucket_arn.value}/*" # Object-level permissions for blob operations
        ]
      }
    ]
  })
}

# IAM Policies for Service Account - SSM
resource "aws_iam_role_policy" "ssm_policy" {
  name = "open-saves-ssm-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SSM Parameter Store permissions
        # Used for: reading application configuration parameters
        Action = [
          "ssm:GetParameter",   # Get individual parameter
          "ssm:GetParameters"   # Get multiple parameters
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/open-saves/*",      # Open Saves specific parameters
          "arn:aws:ssm:${var.region}:*:parameter/etc/open-saves/*"   # Configuration file parameters
        ]
      }
    ]
  })
}

# S3 bucket policy with necessary permissions for Open Saves
resource "aws_s3_bucket_policy" "blobs" {
  bucket = data.aws_ssm_parameter.s3_bucket_id.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.service_account_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${data.aws_ssm_parameter.s3_bucket_arn.value}/*"
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.service_account_role.arn
        }
        Action   = "s3:ListBucket"
        Resource = data.aws_ssm_parameter.s3_bucket_arn.value
      }
    ]
  })
  
  # Ensure the service account role is created first
  depends_on = [
    aws_iam_role.service_account_role
  ]
}

# Kubernetes Resources
resource "kubernetes_namespace" "open_saves" {
  metadata {
    name = var.namespace
    labels = {
      name        = var.namespace
      environment = var.environment
      project     = "open-saves"
    }
  }
}

resource "kubernetes_service_account" "open_saves" {
  metadata {
    name      = "open-saves-sa"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service_account_role.arn
    }
    labels = {
      app         = "open-saves"
      environment = var.environment
      project     = "open-saves"
    }
  }
}

resource "kubernetes_config_map" "open_saves" {
  metadata {
    name      = "open-saves-config"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
    labels = {
      app         = "open-saves"
      environment = var.environment
      project     = "open-saves"
    }
  }

  data = {
    "config.yaml" = <<-EOT
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "${var.region}"
  dynamodb:
    stores_table: "${local.dynamodb_table_names[0]}"
    records_table: "${local.dynamodb_table_names[1]}"
    metadata_table: "${local.dynamodb_table_names[2]}"
  s3:
    bucket_name: "${data.aws_ssm_parameter.s3_bucket_name.value}"
  elasticache:
    address: "${data.aws_ssm_parameter.redis_endpoint.value}"
    ttl: 3600
  ecr:
    repository_uri: "${data.aws_ssm_parameter.ecr_repo_uri.value}"
EOT
  }
}

resource "kubernetes_deployment" "open_saves" {
  metadata {
    name      = "open-saves"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
    labels = {
      app         = "open-saves"
      environment = var.environment
      project     = "open-saves"
      architecture = var.architecture
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "open-saves"
      }
    }

    template {
      metadata {
        labels = {
          app          = "open-saves"
          environment  = var.environment
          project      = "open-saves"
          architecture = var.architecture
        }
      }

      spec {
        service_account_name = kubernetes_service_account.open_saves.metadata[0].name
        
        node_selector = {
          "kubernetes.io/arch" = var.architecture
        }
        
        container {
          name  = "open-saves"
          image = data.aws_ssm_parameter.container_image_uri.value
          
          command = ["/app/open-saves-aws"]
          args    = ["--config", "/etc/open-saves/config.yaml"]
          
          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
          
          port {
            container_port = 8080
            name          = "http"
          }
          
          port {
            container_port = 8081
            name          = "grpc"
          }
          
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          
          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/open-saves"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
        
        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.open_saves.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "open_saves" {
  metadata {
    name      = "open-saves"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
    labels = {
      app         = "open-saves"
      environment = var.environment
      project     = "open-saves"
    }
  }

  spec {
    selector = {
      app = "open-saves"
    }
    
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
    
    port {
      name        = "grpc"
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
    }
    
    type = "LoadBalancer"
  }
}

# Store outputs in SSM Parameter Store for other steps
resource "aws_ssm_parameter" "load_balancer_hostname" {
  name  = "/open-saves/step4/load_balancer_hostname_${var.architecture}"
  type  = "String"
  value = kubernetes_service.open_saves.status.0.load_balancer.0.ingress.0.hostname

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step4"
    Architecture = var.architecture
  }

  depends_on = [kubernetes_service.open_saves]
}

resource "aws_ssm_parameter" "service_account_role_arn" {
  name  = "/open-saves/step4/service_account_role_arn_${var.architecture}"
  type  = "String"
  value = aws_iam_role.service_account_role.arn

  tags = {
    Environment  = var.environment
    Project      = "open-saves"
    Step         = "step4"
    Architecture = var.architecture
  }
}
