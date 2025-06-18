output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.cluster.certificate_authority[0].data
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.eks_vpc.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "ecr_repo_uri" {
  description = "URI of the ECR repository"
  value       = aws_ecr_repository.open_saves.repository_url
}

output "oidc_provider" {
  description = "OIDC provider URL for the EKS cluster"
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  value       = aws_iam_openid_connect_provider.eks.arn
}
