resource "null_resource" "build_and_push_image" {
  triggers = {
    # This will cause the resource to be recreated when any of the source files change
    # or when the architecture changes
    source_hash = "${var.source_hash}"
    architecture = "${var.architecture}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Use absolute path to ensure we're in the right directory
      cd /home/ec2-user/projects/open-saves-aws/aws
      
      # Create config directory if it doesn't exist
      mkdir -p config
      
      # Get the account ID for the S3 bucket name if not provided
      S3_BUCKET_NAME="${var.s3_bucket_name}"
      if [ -z "$S3_BUCKET_NAME" ]; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        S3_BUCKET_NAME="open-saves-blobs-$ACCOUNT_ID"
      fi
      
      # Get the Redis endpoint if not provided
      REDIS_ENDPOINT="${var.redis_endpoint}"
      if [ -z "$REDIS_ENDPOINT" ]; then
        # Default to a placeholder that will be updated later
        REDIS_ENDPOINT="redis-endpoint-to-be-updated:6379"
      fi
      
      # Create a minimal config.yaml file if it doesn't exist
      if [ ! -f config/config.yaml ]; then
        echo "Creating minimal config.yaml file..."
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
    repository_uri: "${var.ecr_repo_uri}"
EOF
      fi
      
      # Also create the SSM parameter with JSON format for the config
      echo "Creating SSM parameter with JSON format..."
      python3 -c "import yaml, json, sys; print(json.dumps(yaml.safe_load(open('config/config.yaml').read())))" > config/config.json
      aws ssm put-parameter --name "/etc/open-saves/config.yaml" --type "String" --value file://config/config.json --overwrite --region ${var.region}
      
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
