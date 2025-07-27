#!/bin/bash

# Deploy Step 1: EKS Cluster and ECR Repository
# This step creates the base infrastructure: VPC, EKS cluster, and ECR repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step1-cluster-ecr"

# Default values
REGION="us-east-1"
CLUSTER_NAME="open-saves-cluster"
ECR_REPO_NAME="open-saves"
ENVIRONMENT="dev"

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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --cluster-name NAME          EKS cluster name (default: open-saves-cluster)"
            echo "  --ecr-repo-name NAME         ECR repository name (default: open-saves)"
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

echo "=========================================="
echo "Deploying Step 1: EKS Cluster and ECR"
echo "=========================================="
echo "Region: $REGION"
echo "Cluster Name: $CLUSTER_NAME"
echo "ECR Repository: $ECR_REPO_NAME"
echo "Environment: $ENVIRONMENT"
echo ""

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
    -var="cluster_name=$CLUSTER_NAME" \
    -var="ecr_repo_name=$ECR_REPO_NAME" \
    -var="environment=$ENVIRONMENT" \
    -out=tfplan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo "=========================================="
echo "Step 1 deployment completed successfully!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "- VPC with public and private subnets"
echo "- EKS cluster: $CLUSTER_NAME"
echo "- ECR repository: $ECR_REPO_NAME"
echo "- IAM roles and policies"
echo "- OIDC provider for service accounts"
echo ""
echo "Configuration stored in SSM Parameter Store under /open-saves/step1/"
echo ""
echo "Next step: Run deploy-step2.sh to create the data infrastructure"
