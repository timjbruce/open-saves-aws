terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ECR Repository
resource "aws_ecr_repository" "open_saves" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "open-saves-ecr"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# VPC for EKS
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                        = "${var.cluster_name}-vpc"
    Environment                                 = var.environment
    Project                                     = "open-saves"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Public subnets
resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone       = "${var.region}${["a", "b", "d"][count.index]}"
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-${count.index}"
    Environment                                 = var.environment
    Project                                     = "open-saves"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private subnets
resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 3)
  availability_zone = "${var.region}${["a", "b", "d"][count.index]}"

  tags = {
    Name                                        = "${var.cluster_name}-private-${count.index}"
    Environment                                 = var.environment
    Project                                     = "open-saves"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name        = "${var.cluster_name}-igw"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.cluster_name}-nat-eip"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name        = "${var.cluster_name}-nat"
    Environment = var.environment
    Project     = "open-saves"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.cluster_name}-public-rt"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "${var.cluster_name}-private-rt"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# EKS Cluster IAM Role
resource "aws_iam_role" "cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-cluster-role"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Attach policies to cluster role
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster_role.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
    Project     = "open-saves"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]
}

# OIDC provider for EKS
data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.cluster_name}-oidc"
    Environment = var.environment
    Project     = "open-saves"
  }
}

# Store outputs in SSM Parameter Store for other steps
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/open-saves/step1/vpc_id"
  type  = "String"
  value = aws_vpc.eks_vpc.id

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/open-saves/step1/private_subnet_ids"
  type  = "StringList"
  value = join(",", aws_subnet.private[*].id)

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/open-saves/step1/public_subnet_ids"
  type  = "StringList"
  value = join(",", aws_subnet.public[*].id)

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "ecr_repo_uri" {
  name  = "/open-saves/step1/ecr_repo_uri"
  type  = "String"
  value = aws_ecr_repository.open_saves.repository_url

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name  = "/open-saves/step1/cluster_endpoint"
  type  = "String"
  value = aws_eks_cluster.cluster.endpoint

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "cluster_certificate_authority_data" {
  name  = "/open-saves/step1/cluster_certificate_authority_data"
  type  = "String"
  value = aws_eks_cluster.cluster.certificate_authority[0].data

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "cluster_security_group_id" {
  name  = "/open-saves/step1/cluster_security_group_id"
  type  = "String"
  value = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "oidc_provider" {
  name  = "/open-saves/step1/oidc_provider"
  type  = "String"
  value = replace(aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "oidc_provider_arn" {
  name  = "/open-saves/step1/oidc_provider_arn"
  type  = "String"
  value = aws_iam_openid_connect_provider.eks.arn

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/open-saves/step1/cluster_name"
  type  = "String"
  value = var.cluster_name

  tags = {
    Environment = var.environment
    Project     = "open-saves"
    Step        = "step1"
  }
}
