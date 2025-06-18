provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = var.eks_endpoint
  cluster_ca_certificate = base64decode(var.eks_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "nodes" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.architecture}-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = var.architecture == "arm64" ? ["t4g.medium"] : ["t3.medium"]
  
  # Use the appropriate AMI based on architecture
  ami_type = var.architecture == "arm64" ? "AL2_ARM_64" : "AL2_x86_64"

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

# Add SSM Parameter Store read access
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
        Resource = "arn:aws:ssm:${var.region}:*:parameter/open-saves/*"
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
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${var.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:open-saves-sa"
          }
        }
      }
    ]
  })
}

# IAM Policies for Service Account
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "open-saves-dynamodb-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*"
        ]
        Effect   = "Allow"
        Resource = var.dynamodb_table_arns
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_policy" {
  name = "open-saves-s3-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ssm_policy" {
  name = "open-saves-ssm-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:*:parameter/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "elasticache_policy" {
  name = "open-saves-elasticache-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "elasticache:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Kubernetes Resources
resource "kubernetes_namespace" "open_saves" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_service_account" "open_saves" {
  metadata {
    name      = "open-saves-sa"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.service_account_role.arn
    }
  }
}

resource "kubernetes_config_map" "open_saves" {
  metadata {
    name      = "open-saves-config"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
  }

  data = {
    "config.yaml" = <<-EOT
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "${var.region}"
  dynamodb:
    stores_table: "${var.dynamodb_table_names.stores}"
    records_table: "${var.dynamodb_table_names.records}"
    metadata_table: "${var.dynamodb_table_names.metadata}"
  s3:
    bucket_name: "${var.s3_bucket_name}"
  elasticache:
    address: "${var.redis_endpoint}"
    ttl: 3600
  ecr:
    repository_uri: "${var.ecr_repo_uri}"
EOT
  }
}

resource "kubernetes_deployment" "open_saves" {
  metadata {
    name      = "open-saves"
    namespace = kubernetes_namespace.open_saves.metadata[0].name
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
          app = "open-saves"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.open_saves.metadata[0].name
        
        node_selector = {
          "kubernetes.io/arch" = var.architecture
        }
        
        container {
          name  = "open-saves"
          image = "${var.ecr_repo_uri}:${var.architecture}"
          
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
          }
          
          port {
            container_port = 8081
          }
          
          env {
            name  = "AWS_REGION"
            value = var.region
          }
          
          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/open-saves"
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
  }

  spec {
    selector = {
      app = "open-saves"
    }
    
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
    
    port {
      name        = "grpc"
      port        = 8081
      target_port = 8081
    }
    
    type = "LoadBalancer"
  }
}
