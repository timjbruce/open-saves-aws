#!/bin/bash

# Deploy Step 5: CloudFront & WAF
# This step should be deployed once per environment (architecture-agnostic)
# NOTE: This step requires the load balancer to exist first (Step 4)

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

echo "Deploying Step 5: CloudFront & WAF"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"

# Check if load balancer exists
echo "Checking if load balancer exists..."
LB_DNS=$(terraform output -raw load_balancer_hostname 2>/dev/null || echo "")
if [ -z "$LB_DNS" ]; then
    echo "Error: Load balancer not found. Please deploy Step 4 (Compute App) first."
    echo "CloudFront needs the load balancer DNS name to configure its origin."
    exit 1
fi

echo "Load balancer found: $LB_DNS"

# Deploy Step 5
terraform apply -target=module.step5_cloudfront_waf \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

echo "Step 5 deployment completed successfully!"
echo "CloudFront distribution and WAF are now ready."
echo "CloudFront URL: $(terraform output -raw cloudfront_domain_name 2>/dev/null || echo 'Check AWS Console')"
