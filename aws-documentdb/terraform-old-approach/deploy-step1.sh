#!/bin/bash

# Deploy Step 1: Base Infrastructure (VPC, EKS, ECR)
# This step should be deployed once per environment

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

echo "Deploying Step 1: Base Infrastructure"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    terraform init
fi

# Deploy only Step 1
terraform apply -target=module.step1_base_infrastructure \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

echo "Step 1 deployment completed successfully!"
echo "VPC, EKS cluster, and ECR repository are now ready."
