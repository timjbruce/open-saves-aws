provider "aws" {
  region = var.region
}

resource "aws_ecr_repository" "open_saves" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # EKS cluster without compute nodes initially
  create_node_security_group = true
  create_cluster_security_group = true
  
  # Enable OIDC provider
  enable_irsa = true
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "${var.cluster_name}-vpc"
  cidr = "192.168.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}d"]
  private_subnets = ["192.168.96.0/19", "192.168.128.0/19", "192.168.160.0/19"]
  public_subnets  = ["192.168.0.0/19", "192.168.32.0/19", "192.168.64.0/19"]

  enable_nat_gateway = true
  single_nat_gateway = true
  
  # Tags for EKS
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

# Store ECR repository URI in a local file for use between steps
resource "local_file" "env_deploy" {
  content  = "ECR_REPO_URI=${aws_ecr_repository.open_saves.repository_url}"
  filename = "${path.module}/../../.env.deploy"
}
