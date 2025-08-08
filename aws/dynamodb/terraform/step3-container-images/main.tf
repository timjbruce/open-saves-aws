terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Get data from previous steps via SSM Parameter Store
data "aws_ssm_parameter" "ecr_repo_uri" {
  name = "/open-saves/step1/ecr_repo_uri"
}

data "aws_ssm_parameter" "s3_bucket_name" {
  name = "/open-saves/step2/s3_bucket_name"
}

data "aws_ssm_parameter" "redis_endpoint" {
  name = "/open-saves/step2/redis_endpoint"
}

# Build and push container images
resource "null_resource" "build_and_push_image" {
  triggers = {
    # This will cause the resource to be recreated when any of the source files change
    # or when the architecture changes
    source_hash  = var.source_hash
    architecture = var.architecture
    # Add timestamp to force rebuild if needed
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Use absolute path to ensure we're in the right directory
      cd ${var.source_path}
      
      # Create config directory if it doesn't exist
      mkdir -p config
      
      # Get the S3 bucket name and Redis endpoint from SSM
      S3_BUCKET_NAME="${data.aws_ssm_parameter.s3_bucket_name.value}"
      REDIS_ENDPOINT="${data.aws_ssm_parameter.redis_endpoint.value}"
      ECR_REPO_URI="${data.aws_ssm_parameter.ecr_repo_uri.value}"
      
      # Create a minimal config.yaml file
      echo "Creating config.yaml file..."
      cat > config/config.yaml <<EOF
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "${var.region}"
  dynamodb:
    stores_table: "open-saves-stores"
    records_table: "open-saves-records"
    metadata_table: "open-saves-metadata"
  s3:
    bucket_name: "$S3_BUCKET_NAME"
  elasticache:
    address: "$REDIS_ENDPOINT"
    ttl: 3600
  ecr:
    repository_uri: "$ECR_REPO_URI"
EOF
      
      # Build for AMD64
      if [[ "${var.architecture}" == "amd64" || "${var.architecture}" == "both" ]]; then
        echo "Building AMD64 image..."
        GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .
        docker build -f Dockerfile -t $ECR_REPO_URI:amd64 .
        aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin $ECR_REPO_URI
        docker push $ECR_REPO_URI:amd64
        docker tag $ECR_REPO_URI:amd64 $ECR_REPO_URI:latest
        docker push $ECR_REPO_URI:latest
      fi
      
      # Build for ARM64
      if [[ "${var.architecture}" == "arm64" || "${var.architecture}" == "both" ]]; then
        echo "Building ARM64 image..."
        GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o open-saves-aws-arm64 .
        docker build -f Dockerfile.arm64 -t $ECR_REPO_URI:arm64 .
        aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin $ECR_REPO_URI
        docker push $ECR_REPO_URI:arm64
      fi
      
      echo "Container image build and push completed for architecture: ${var.architecture}"
    EOT
  }
}

# Store outputs in SSM Parameter Store for other steps
resource "aws_ssm_parameter" "container_image_uri" {
  name      = "/open-saves/step3/container_image_uri_${var.architecture}"
  type      = "String"
  value     = "${data.aws_ssm_parameter.ecr_repo_uri.value}:${var.architecture}"
  overwrite = true

  tags = {
    Environment  = var.environment
    Project      = "open-saves"
    Step         = "step3"
    Architecture = var.architecture
  }

  depends_on = [null_resource.build_and_push_image]
}
