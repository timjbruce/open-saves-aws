#!/bin/bash

# Master deployment script for Open Saves with architecture switching
# This script demonstrates the new workflow that avoids CloudFront recreation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function to display usage
usage() {
    echo "Usage: $0 [COMMAND] [ARCHITECTURE]"
    echo ""
    echo "Commands:"
    echo "  full-deploy     Deploy complete environment (Steps 1-5)"
    echo "  switch-arch     Switch architecture (Steps 4-5 only)"
    echo "  deploy-cf       Deploy CloudFront (Step 3 only)"
    echo "  teardown-arch   Remove architecture-specific resources (Steps 5-4)"
    echo "  full-teardown   Complete teardown (Steps 5-1)"
    echo ""
    echo "Architecture:"
    echo "  amd64          Deploy for AMD64 architecture"
    echo "  arm64          Deploy for ARM64 architecture"
    echo ""
    echo "Examples:"
    echo "  $0 full-deploy arm64      # Deploy complete environment with ARM64"
    echo "  $0 switch-arch amd64      # Switch from ARM64 to AMD64 (keeps CloudFront)"
    echo "  $0 deploy-cf              # Deploy CloudFront only"
    echo "  $0 teardown-arch arm64    # Remove ARM64 resources only"
    echo "  $0 full-teardown          # Remove everything"
}

# Check arguments
if [ $# -lt 1 ]; then
    usage
    exit 1
fi

COMMAND=$1
ARCHITECTURE=${2:-arm64}

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be either 'amd64' or 'arm64'"
    exit 1
fi

# Set environment variables
export ARCHITECTURE=$ARCHITECTURE
export AWS_REGION=${AWS_REGION:-us-west-2}
export ENVIRONMENT=${ENVIRONMENT:-dev}

echo "=== Open Saves Deployment ==="
echo "Command: $COMMAND"
echo "Architecture: $ARCHITECTURE"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"
echo "================================"

case $COMMAND in
    "full-deploy")
        echo "Deploying complete environment..."
        echo "Step 1: Base Infrastructure"
        ./deploy-step1.sh
        echo ""
        echo "Step 2: Data Layer"
        ./deploy-step2.sh
        echo ""
        echo "Step 4: Container Images"
        ./deploy-step4.sh
        echo ""
        echo "Step 5: Compute App"
        ./deploy-step5.sh
        echo ""
        echo "Step 3: CloudFront & WAF"
        ./deploy-step3.sh
        echo ""
        echo "✅ Full deployment completed!"
        echo "Your Open Saves environment is ready on $ARCHITECTURE architecture."
        ;;
        
    "switch-arch")
        echo "Switching to $ARCHITECTURE architecture..."
        echo "This will keep CloudFront and data layer intact."
        echo ""
        echo "Step 1: Tearing down current compute resources"
        ./teardown-step5.sh
        echo ""
        echo "Step 2: Building new container images"
        ./deploy-step4.sh
        echo ""
        echo "Step 3: Deploying new compute resources"
        ./deploy-step5.sh
        echo ""
        echo "✅ Architecture switch completed!"
        echo "Your Open Saves environment is now running on $ARCHITECTURE architecture."
        echo "CloudFront distribution was preserved and is still active."
        ;;
        
    "deploy-cf")
        echo "Deploying CloudFront & WAF..."
        ./deploy-step3.sh
        echo ""
        echo "✅ CloudFront deployment completed!"
        ;;
        
    "teardown-arch")
        echo "Removing architecture-specific resources for $ARCHITECTURE..."
        echo "This will keep base infrastructure, data layer, and CloudFront intact."
        echo ""
        ./teardown-step5.sh
        ./teardown-step4.sh
        echo ""
        echo "✅ Architecture-specific resources removed!"
        echo "Base infrastructure, data layer, and CloudFront are still active."
        ;;
        
    "full-teardown")
        echo "Performing complete teardown..."
        echo "Warning: This will remove ALL resources!"
        echo "Press Ctrl+C within 10 seconds to cancel..."
        sleep 10
        echo ""
        ./teardown-step5.sh
        ./teardown-step4.sh
        ./teardown-step3.sh
        ./teardown-step2.sh
        ./teardown-step1.sh
        echo ""
        echo "✅ Complete teardown completed!"
        echo "All Open Saves resources have been removed."
        ;;
        
    *)
        echo "Error: Unknown command '$COMMAND'"
        usage
        exit 1
        ;;
esac

echo ""
echo "=== Deployment Summary ==="
if [ "$COMMAND" != "full-teardown" ]; then
    echo "Load Balancer: $(terraform output -raw load_balancer_hostname 2>/dev/null || echo 'Not deployed')"
    echo "CloudFront URL: $(terraform output -raw cloudfront_domain_name 2>/dev/null || echo 'Not deployed')"
fi
echo "=========================="
