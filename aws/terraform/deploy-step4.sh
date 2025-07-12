#!/bin/bash

# Deploy Step 4: Compute Nodes & App
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
NAMESPACE=${NAMESPACE:-open-saves}

echo "Deploying Step 4: Compute Nodes & App"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE"
echo "Namespace: $NAMESPACE"

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be either 'amd64' or 'arm64'"
    exit 1
fi

# Deploy Step 4
terraform apply -target=module.step4_compute_app \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    -var="namespace=$NAMESPACE" \
    -auto-approve

echo "Step 4 deployment completed successfully!"
echo "EKS nodes and application pods are now running on $ARCHITECTURE architecture."
echo "Load balancer: $(terraform output -raw load_balancer_hostname 2>/dev/null || echo 'Check AWS Console')"
