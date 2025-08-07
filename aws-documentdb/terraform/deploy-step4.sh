#!/bin/bash

# Deploy Step 4: Compute and Application
# This step creates EKS node groups and deploys the Open Saves application

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step4-compute-app"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
NAMESPACE="open-saves"
ENVIRONMENT="dev"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --architecture)
            ARCHITECTURE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture for compute nodes (amd64|arm64, default: amd64)"
            echo "  --namespace NAMESPACE        Kubernetes namespace (default: open-saves)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --help                       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be 'amd64' or 'arm64'"
    exit 1
fi

echo "=========================================="
echo "Deploying Step 4: Compute and Application"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Namespace: $NAMESPACE"
echo "Environment: $ENVIRONMENT"
echo ""

# Verify prerequisites
echo "Verifying prerequisites..."
REQUIRED_PARAMS=(
    "/open-saves/step1/cluster_name"
    "/open-saves/step2/documentdb_endpoint"
    "/open-saves/step3/container_image_uri_${ARCHITECTURE}"
)

for param in "${REQUIRED_PARAMS[@]}"; do
    if ! aws ssm get-parameter --name "$param" --region "$REGION" >/dev/null 2>&1; then
        echo "Error: Required parameter not found: $param"
        echo "Please ensure previous steps are completed:"
        echo "  - Step 1: deploy-step1.sh"
        echo "  - Step 2: deploy-step2.sh"
        echo "  - Step 3: deploy-step3.sh --architecture $ARCHITECTURE"
        exit 1
    fi
done

# Change to step directory
cd "$STEP_DIR"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Plan the deployment
echo "Planning Terraform deployment..."
terraform plan \
    -var="region=$REGION" \
    -var="architecture=$ARCHITECTURE" \
    -var="namespace=$NAMESPACE" \
    -var="environment=$ENVIRONMENT" \
    -out=tfplan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Wait for load balancer to be ready
echo ""
echo "Waiting for load balancer to be ready..."
LB_HOSTNAME=$(terraform output -raw load_balancer_hostname)
echo "Load balancer hostname: $LB_HOSTNAME"

# Wait up to 10 minutes for the load balancer to be accessible
echo "Checking load balancer accessibility..."
for i in {1..60}; do
    if curl -s --connect-timeout 5 "http://$LB_HOSTNAME:8080/health" >/dev/null 2>&1; then
        echo "Load balancer is accessible!"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Warning: Load balancer may not be fully ready yet. This is normal and it may take a few more minutes."
        echo "You can check the status with: kubectl get pods -n $NAMESPACE"
        break
    fi
    echo "Attempt $i/60: Load balancer not ready yet, waiting 10 seconds..."
    sleep 10
done

echo ""
echo "=========================================="
echo "Step 4 deployment completed successfully!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "- EKS node group for $ARCHITECTURE architecture"
echo "- Kubernetes namespace: $NAMESPACE"
echo "- Open Saves application deployment"
echo "- Load balancer service"
echo "- IAM roles and policies with least privilege"
echo ""
echo "Application endpoints:"
echo "- HTTP API: http://$LB_HOSTNAME:8080"
echo "- gRPC API: $LB_HOSTNAME:8081"
echo ""
echo "Configuration stored in SSM Parameter Store under /open-saves/step4/"
echo ""
echo "Next step: Run deploy-step5.sh --architecture $ARCHITECTURE to add CloudFront and WAF"
