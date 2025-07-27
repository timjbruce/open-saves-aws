#!/bin/bash

# Teardown Step 5: CloudFront & WAF
# This removes the CloudFront distribution and WAF (architecture-agnostic)

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

echo "Tearing down Step 5: CloudFront & WAF"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"

echo "Warning: CloudFront distribution teardown can take 15-20 minutes..."
echo "Press Ctrl+C within 10 seconds to cancel, or wait to continue..."
sleep 10

# Destroy Step 5
terraform destroy -target=module.step5_cloudfront_waf \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

echo "Step 5 teardown completed successfully!"
echo "CloudFront distribution and WAF have been removed."
