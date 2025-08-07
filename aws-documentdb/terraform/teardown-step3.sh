#!/bin/bash

# Teardown Step 3: Container Images
# This step removes container images from ECR (optional, as they don't incur costs when not running)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step3-container-images"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
ENVIRONMENT="dev"
DELETE_IMAGES="false"

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
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --delete-images)
            DELETE_IMAGES="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture to clean up (amd64|arm64|both, default: amd64)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --delete-images              Also delete container images from ECR"
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

echo "=========================================="
echo "Tearing down Step 3: Container Images"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Environment: $ENVIRONMENT"
echo "Delete Images: $DELETE_IMAGES"
echo ""

# Change to step directory
cd "$STEP_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "No Terraform state found. Step 3 may not be deployed or already destroyed."
    
    # Still try to clean up images if requested
    if [ "$DELETE_IMAGES" = "true" ]; then
        echo "Attempting to clean up container images..."
        
        # Get ECR repository URI from SSM if available
        if ECR_REPO_URI=$(aws ssm get-parameter --name "/open-saves/step1/ecr_repo_uri" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
            ECR_REPO_NAME=$(echo "$ECR_REPO_URI" | cut -d'/' -f2)
            
            echo "Deleting container images for architecture: $ARCHITECTURE"
            if [ "$ARCHITECTURE" = "both" ]; then
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=amd64 --region "$REGION" 2>/dev/null || true
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=arm64 --region "$REGION" 2>/dev/null || true
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=latest --region "$REGION" 2>/dev/null || true
            else
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag="$ARCHITECTURE" --region "$REGION" 2>/dev/null || true
                if [ "$ARCHITECTURE" = "amd64" ]; then
                    aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=latest --region "$REGION" 2>/dev/null || true
                fi
            fi
        fi
    fi
    
    exit 0
fi

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Delete container images if requested
if [ "$DELETE_IMAGES" = "true" ]; then
    echo "Deleting container images before destroying Terraform resources..."
    
    # Get ECR repository URI from SSM
    if ECR_REPO_URI=$(aws ssm get-parameter --name "/open-saves/step1/ecr_repo_uri" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
        ECR_REPO_NAME=$(echo "$ECR_REPO_URI" | cut -d'/' -f2)
        
        echo "Deleting container images for architecture: $ARCHITECTURE"
        if [ "$ARCHITECTURE" = "both" ]; then
            aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=amd64 --region "$REGION" 2>/dev/null || true
            aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=arm64 --region "$REGION" 2>/dev/null || true
            aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=latest --region "$REGION" 2>/dev/null || true
        else
            aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag="$ARCHITECTURE" --region "$REGION" 2>/dev/null || true
            if [ "$ARCHITECTURE" = "amd64" ]; then
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids imageTag=latest --region "$REGION" 2>/dev/null || true
            fi
        fi
    fi
fi

# Plan the destruction
echo "Planning Terraform destruction..."
terraform plan -destroy \
    -var="region=$REGION" \
    -var="architecture=$ARCHITECTURE" \
    -var="environment=$ENVIRONMENT" \
    -out=destroy.tfplan

# Apply the destruction
echo "Applying Terraform destruction..."
terraform apply destroy.tfplan

# Clean up plan file
rm -f destroy.tfplan

# Clean up SSM parameters
echo "Cleaning up SSM parameters..."
if [ "$ARCHITECTURE" = "both" ]; then
    aws ssm delete-parameter --name "/open-saves/step3/container_image_uri_amd64" --region "$REGION" 2>/dev/null || true
    aws ssm delete-parameter --name "/open-saves/step3/container_image_uri_arm64" --region "$REGION" 2>/dev/null || true
else
    aws ssm delete-parameter --name "/open-saves/step3/container_image_uri_${ARCHITECTURE}" --region "$REGION" 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "Step 3 teardown completed successfully!"
echo "=========================================="
echo ""
echo "Resources cleaned up:"
echo "- Terraform state for container image builds"
if [ "$DELETE_IMAGES" = "true" ]; then
    echo "- Container images deleted from ECR"
fi
echo "- SSM parameters"
