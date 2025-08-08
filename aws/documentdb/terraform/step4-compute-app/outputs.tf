output "load_balancer_hostname" {
  description = "Hostname of the load balancer"
  value       = kubernetes_service.open_saves.status.0.load_balancer.0.ingress.0.hostname
}

output "service_account_role_arn" {
  description = "ARN of the service account IAM role"
  value       = aws_iam_role.service_account_role.arn
}

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.nodes.arn
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.open_saves.metadata[0].name
}
