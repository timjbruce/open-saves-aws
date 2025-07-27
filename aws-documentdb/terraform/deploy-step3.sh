#!/bin/bash

# Deploy Step 3: Container Images
# This step builds and pushes container images to ECR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step3-container-images"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
SOURCE_PATH="/home/ec2-user/projects/open-saves-aws/aws"
ENVIRONMENT="dev"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --architecture)
            ARCHITECTURE="$2"
            shift 2
            ;;
        --source-path)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture to build (amd64|arm64|both, default: amd64)"
            echo "  --source-path PATH           Path to source code (default: /home/ec2-user/projects/open-saves-aws/aws)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --help                       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" && "$ARCHITECTURE" != "both" ]]; then
    echo "Error: Architecture must be 'amd64', 'arm64', or 'both'"
    exit 1
fi

echo "=========================================="
echo "Deploying Step 3: Container Images"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Source Path: $SOURCE_PATH"
echo "Environment: $ENVIRONMENT"
echo ""

# Verify prerequisites
echo "Verifying prerequisites..."
if ! aws ssm get-parameter --name "/open-saves/step1/ecr_repo_uri" --region "$REGION" >/dev/null 2>&1; then
    echo "Error: Step 1 must be completed first. ECR repository URI not found in SSM Parameter Store."
    echo "Please run deploy-step1.sh first."
    exit 1
fi

if ! aws ssm get-parameter --name "/open-saves/step2/s3_bucket_name" --region "$REGION" >/dev/null 2>&1; then
    echo "Error: Step 2 must be completed first. S3 bucket name not found in SSM Parameter Store."
    echo "Please run deploy-step2.sh first."
    exit 1
fi

# Verify source path exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Error: Source path does not exist: $SOURCE_PATH"
    exit 1
fi

# Verify Go source files exist
if [ ! -f "$SOURCE_PATH/main.go" ]; then
    echo "Error: main.go not found in source path: $SOURCE_PATH"
    exit 1
fi

# Generate source hash for change detection
SOURCE_HASH=$(find "$SOURCE_PATH" -name "*.go" -o -name "Dockerfile*" | xargs md5sum | md5sum | cut -d' ' -f1)

# Change to step directory
cd "$STEP_DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Plan the deployment
echo "Planning Terraform deployment..."
terraform plan \
    -var="region=$REGION" \
    -var="architecture=$ARCHITECTURE" \
    -var="source_path=$SOURCE_PATH" \
    -var="source_hash=$SOURCE_HASH" \
    -var="environment=$ENVIRONMENT" \
    -out=tfplan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo "=========================================="
echo "Step 3 deployment completed successfully!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "- Container image built for $ARCHITECTURE architecture"
echo "- Image pushed to ECR repository"
echo "- Configuration updated in source directory"
echo ""
echo "Container image URI stored in SSM Parameter Store under /open-saves/step3/"
echo ""
echo "Next step: Run deploy-step4.sh --architecture $ARCHITECTURE to deploy compute resources"
