#!/bin/bash

# Teardown Step 3: Container Images
# This removes the architecture-specific container images

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

echo "Tearing down Step 3: Container Images"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE"

# Note: Container images in ECR are not managed by Terraform destroy
# They need to be manually deleted or will be overwritten on next build
echo "Note: Container images in ECR are not automatically deleted."
echo "To manually delete images for $ARCHITECTURE:"
echo "aws ecr list-images --repository-name dev-open-saves --region $REGION"
echo "aws ecr batch-delete-image --repository-name dev-open-saves --image-ids imageTag=$ARCHITECTURE --region $REGION"

# Destroy Step 3 (this mainly cleans up any temporary resources)
terraform destroy -target=module.step3_container_images \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    -auto-approve

echo "Step 3 teardown completed successfully!"
