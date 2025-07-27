output "image_tag" {
  description = "Tag of the built image"
  value       = var.architecture
}

output "build_complete" {
  description = "Indicates that the build is complete"
  value       = null_resource.build_and_push_image.id
}
