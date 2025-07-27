#!/bin/bash

# Teardown Step 4: Compute Nodes & App
# This removes the architecture-specific compute resources

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

echo "Tearing down Step 4: Compute Nodes & App"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE"

# Destroy Step 4
terraform destroy -target=module.step4_compute_app \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    -auto-approve

echo "Step 4 teardown completed successfully!"
echo "EKS nodes and application pods for $ARCHITECTURE architecture have been removed."
