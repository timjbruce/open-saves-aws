output "load_balancer_hostname" {
  description = "Hostname of the load balancer"
  value       = kubernetes_service.open_saves.status.0.load_balancer.0.ingress.0.hostname
}

output "node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.nodes.node_group_name
}

output "namespace" {
  description = "Kubernetes namespace for Open Saves"
  value       = kubernetes_namespace.open_saves.metadata[0].name
}
