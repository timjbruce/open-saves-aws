resource "null_resource" "build_and_push_image" {
  triggers = {
    # This will cause the resource to be recreated when any of the source files change
    source_hash = "${var.source_hash}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${var.source_path}
      
      # Build for AMD64
      if [[ "${var.architecture}" == "amd64" || "${var.architecture}" == "both" ]]; then
        echo "Building AMD64 image..."
        GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .
        docker build -f Dockerfile -t ${var.ecr_repo_uri}:amd64 .
        aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.ecr_repo_uri}
        docker push ${var.ecr_repo_uri}:amd64
        docker tag ${var.ecr_repo_uri}:amd64 ${var.ecr_repo_uri}:latest
        docker push ${var.ecr_repo_uri}:latest
      fi
      
      # Build for ARM64
      if [[ "${var.architecture}" == "arm64" || "${var.architecture}" == "both" ]]; then
        echo "Building ARM64 image..."
        GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o open-saves-aws-arm64 .
        docker build -f Dockerfile.arm64 -t ${var.ecr_repo_uri}:arm64 .
        aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.ecr_repo_uri}
        docker push ${var.ecr_repo_uri}:arm64
      fi
    EOT
  }
}
