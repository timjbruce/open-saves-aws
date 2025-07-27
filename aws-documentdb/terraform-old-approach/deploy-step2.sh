#!/bin/bash

# Deploy Step 2: Data Layer (S3, DynamoDB, Redis)
# This step should be deployed once per environment
# Requires architecture parameter for Redis instance type selection

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
ARCHITECTURE=${ARCHITECTURE:-arm64}

echo "Deploying Step 2: Data Layer"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE (for Redis instance type)"

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be either 'amd64' or 'arm64'"
    exit 1
fi

# Deploy Step 2
terraform apply -target=module.step2_data_layer \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    -auto-approve

echo "Step 2 deployment completed successfully!"
echo "S3 bucket, DynamoDB tables, and Redis cluster are now ready."
