output "container_image_uri" {
  description = "URI of the built container image"
  value       = "${data.aws_ssm_parameter.ecr_repo_uri.value}:${var.architecture}"
}

output "ecr_repo_uri" {
  description = "Base URI of the ECR repository"
  value       = data.aws_ssm_parameter.ecr_repo_uri.value
}
