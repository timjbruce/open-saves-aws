#!/bin/bash

# Deploy Step 3: Container Images
# This step should be deployed per architecture

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

echo "Deploying Step 3: Container Images"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE"

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be either 'amd64' or 'arm64'"
    exit 1
fi

# Generate source hash based on current source code
SOURCE_HASH=$(find ../../aws -name "*.go" -o -name "*.mod" -o -name "Dockerfile*" | xargs sha256sum | sha256sum | cut -d' ' -f1)

echo "Source hash: $SOURCE_HASH"

# Deploy Step 3
terraform apply -target=module.step3_container_images \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    -var="source_hash=$SOURCE_HASH" \
    -auto-approve

echo "Step 3 deployment completed successfully!"
echo "Container image built and pushed to ECR for $ARCHITECTURE architecture."
