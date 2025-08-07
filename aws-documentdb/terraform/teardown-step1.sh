#!/bin/bash

# Teardown Step 1: EKS Cluster and ECR Repository
# This step destroys the base infrastructure: VPC, EKS cluster, and ECR repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step1-cluster-ecr"

# Default values
REGION="us-east-1"
CLUSTER_NAME="open-saves-cluster"
ECR_REPO_NAME="open-saves"
ENVIRONMENT="dev"
DELETE_ECR_IMAGES="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --ecr-repo-name)
            ECR_REPO_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --delete-ecr-images)
            DELETE_ECR_IMAGES="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --cluster-name NAME          EKS cluster name (default: open-saves-cluster)"
            echo "  --ecr-repo-name NAME         ECR repository name (default: open-saves)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --delete-ecr-images          Delete all images from ECR before destroying repository"
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
echo "Tearing down Step 1: EKS Cluster and ECR"
echo "=========================================="
echo "Region: $REGION"
echo "Cluster Name: $CLUSTER_NAME"
echo "ECR Repository: $ECR_REPO_NAME"
echo "Environment: $ENVIRONMENT"
echo "Delete ECR Images: $DELETE_ECR_IMAGES"
echo ""

# Change to step directory
cd "$STEP_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "No Terraform state found. Step 1 may not be deployed or already destroyed."
    
    # Still try to clean up ECR images if requested
    if [ "$DELETE_ECR_IMAGES" = "true" ]; then
        echo "Attempting to clean up ECR images..."
        
        # List and delete all images in the repository
        if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
            echo "Deleting all images from ECR repository: $ECR_REPO_NAME"
            
            # Get all image tags and digests
            IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$REGION" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
            
            if [ "$IMAGE_IDS" != "[]" ] && [ "$IMAGE_IDS" != "" ]; then
                echo "Found images to delete, removing them..."
                aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids "$IMAGE_IDS" --region "$REGION" 2>/dev/null || true
            else
                echo "No images found in repository"
            fi
        else
            echo "ECR repository $ECR_REPO_NAME not found or already deleted"
        fi
    fi
    
    exit 0
fi

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Delete ECR images if requested
if [ "$DELETE_ECR_IMAGES" = "true" ]; then
    echo "Deleting all images from ECR repository before destruction..."
    
    # List and delete all images in the repository
    if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo "Deleting all images from ECR repository: $ECR_REPO_NAME"
        
        # Get all image tags and digests
        IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO_NAME" --region "$REGION" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
        
        if [ "$IMAGE_IDS" != "[]" ] && [ "$IMAGE_IDS" != "" ]; then
            echo "Found images to delete, removing them..."
            aws ecr batch-delete-image --repository-name "$ECR_REPO_NAME" --image-ids "$IMAGE_IDS" --region "$REGION" 2>/dev/null || true
        else
            echo "No images found in repository"
        fi
    else
        echo "ECR repository $ECR_REPO_NAME not found"
    fi
fi

# Plan the destruction
echo "Planning Terraform destruction..."
terraform plan -destroy \
    -var="region=$REGION" \
    -var="cluster_name=$CLUSTER_NAME" \
    -var="ecr_repo_name=$ECR_REPO_NAME" \
    -var="environment=$ENVIRONMENT" \
    -out=destroy.tfplan

# Apply the destruction
echo "Applying Terraform destruction..."
terraform apply destroy.tfplan

# Clean up plan file
rm -f destroy.tfplan

# Clean up SSM parameters
echo "Cleaning up SSM parameters..."
aws ssm delete-parameter --name "/open-saves/step1/vpc_id" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/private_subnet_ids" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/public_subnet_ids" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/ecr_repo_uri" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/cluster_endpoint" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/cluster_certificate_authority_data" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/cluster_security_group_id" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/oidc_provider" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/oidc_provider_arn" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step1/cluster_name" --region "$REGION" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Step 1 teardown completed successfully!"
echo "=========================================="
echo ""
echo "Resources destroyed:"
echo "- EKS cluster: $CLUSTER_NAME"
echo "- VPC with all subnets, route tables, and gateways"
echo "- ECR repository: $ECR_REPO_NAME"
if [ "$DELETE_ECR_IMAGES" = "true" ]; then
    echo "- All container images from ECR"
fi
echo "- IAM roles and policies"
echo "- OIDC provider"
echo "- SSM parameters"
echo ""
echo "All Open Saves infrastructure has been completely removed."
