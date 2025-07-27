#!/bin/bash

# Teardown Step 2: Data Layer (S3, DynamoDB, Redis)
# This removes the data storage resources

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

echo "Tearing down Step 2: Data Layer"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"

echo "Warning: This will delete S3 bucket, DynamoDB tables, and Redis cluster!"
echo "Make sure to backup any important data first."
echo "Press Ctrl+C within 10 seconds to cancel, or wait to continue..."
sleep 10

# Empty S3 bucket first (required before deletion)
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
if [ -n "$S3_BUCKET" ]; then
    echo "Emptying S3 bucket: $S3_BUCKET"
    aws s3 rm s3://$S3_BUCKET --recursive --region $REGION || echo "S3 bucket may already be empty"
fi

# Destroy Step 2
terraform destroy -target=module.step2_data_layer \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -auto-approve

echo "Step 2 teardown completed successfully!"
echo "S3 bucket, DynamoDB tables, and Redis cluster have been removed."
