#!/bin/bash

# Teardown Step 1: Base Infrastructure (VPC, EKS, ECR)
# This removes the foundational infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source environment variables if they exist
if [ -f .env.deploy ]; then
    source .env.deploy
fi

# Set default values
REGION=${AWS_REGION:-us-west-2}
ENVIRONMENT=${ENVIRONMENT:-dev}

echo "Tearing down Step 1: Base Infrastructure"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"

echo "Warning: This will delete the EKS cluster, VPC, and ECR repository!"
echo "Make sure all other resources have been removed first."
echo "Press Ctrl+C within 10 seconds to cancel, or wait to continue..."
sleep 10

# Clean up ECR repository first
ECR_REPO=$(terraform output -raw ecr_repo_name 2>/dev/null || echo "")
if [ -n "$ECR_REPO" ]; then
    echo "Cleaning up ECR repository: $ECR_REPO"
    aws ecr delete-repository --repository-name $ECR_REPO --force --region $REGION || echo "ECR repository may already be deleted"
fi

# Destroy Step 1
terraform destroy -target=module.step1_base_infrastructure \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

echo "Step 1 teardown completed successfully!"
echo "VPC, EKS cluster, and ECR repository have been removed."
