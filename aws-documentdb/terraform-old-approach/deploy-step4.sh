#!/bin/bash

# Deploy Step 4: Compute Nodes & App
# This deploys the architecture-specific compute resources

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --region)
            REGION="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --architecture|-a)
            ARCHITECTURE="$2"
            shift 2
            ;;
        --instance-types)
            INSTANCE_TYPES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "Deploying Step 4: Compute Nodes & App"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Architecture: $ARCHITECTURE"

# Prepare instance types variable if provided
INSTANCE_TYPES_VAR=""
if [ -n "$INSTANCE_TYPES" ]; then
    if [ "$ARCHITECTURE" == "arm64" ]; then
        INSTANCE_TYPES_VAR="-var='instance_types={\"arm64\":[\"$INSTANCE_TYPES\"],\"amd64\":[\"t3.medium\"]}'"
    elif [ "$ARCHITECTURE" == "amd64" ]; then
        INSTANCE_TYPES_VAR="-var='instance_types={\"arm64\":[\"t4g.medium\"],\"amd64\":[\"$INSTANCE_TYPES\"]}'"
    fi
    echo "Using custom instance types: $INSTANCE_TYPES"
fi

# Deploy Step 4
eval terraform apply -target=module.step4_compute_app \
    -var="region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="architecture=$ARCHITECTURE" \
    $INSTANCE_TYPES_VAR \
    -auto-approve

echo "Step 4 deployment completed successfully!"
echo "EKS nodes and application pods for $ARCHITECTURE architecture are now running."
echo "Load balancer hostname: $(terraform output -raw load_balancer_hostname)"
