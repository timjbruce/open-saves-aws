#!/bin/bash

# Architecture Switching Script for Open Saves AWS
# This script switches between AMD64 and ARM64 architectures by tearing down
# and redeploying the architecture-specific steps (3, 4, 5)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
REGION="us-east-1"
FROM_ARCH=""
TO_ARCH=""
NAMESPACE="open-saves"
ENVIRONMENT="dev"
SOURCE_PATH="/home/ec2-user/projects/open-saves-aws/aws"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect current architecture
detect_current_architecture() {
    local current_arch=""
    
    # Check for AMD64 deployment
    if aws ssm get-parameter --name "/open-saves/step4/load_balancer_hostname_amd64" --region "$REGION" >/dev/null 2>&1; then
        if [ -n "$current_arch" ]; then
            print_warning "Both AMD64 and ARM64 deployments detected. Please specify --from-arch"
            return 1
        fi
        current_arch="amd64"
    fi
    
    # Check for ARM64 deployment
    if aws ssm get-parameter --name "/open-saves/step4/load_balancer_hostname_arm64" --region "$REGION" >/dev/null 2>&1; then
        if [ -n "$current_arch" ]; then
            print_warning "Both AMD64 and ARM64 deployments detected. Please specify --from-arch"
            return 1
        fi
        current_arch="arm64"
    fi
    
    if [ -z "$current_arch" ]; then
        print_error "No current deployment detected. Please deploy first using deploy-full.sh"
        return 1
    fi
    
    echo "$current_arch"
}

# Function to validate prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check that Steps 1 and 2 are deployed
    if ! aws ssm get-parameter --name "/open-saves/step1/vpc_id" --region "$REGION" >/dev/null 2>&1; then
        print_error "Step 1 (EKS Cluster and ECR) must be deployed first"
        exit 1
    fi
    
    if ! aws ssm get-parameter --name "/open-saves/step2/s3_bucket_name" --region "$REGION" >/dev/null 2>&1; then
        print_error "Step 2 (Data Infrastructure) must be deployed first"
        exit 1
    fi
    
    print_success "Prerequisites satisfied"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --from-arch)
            FROM_ARCH="$2"
            shift 2
            ;;
        --to-arch)
            TO_ARCH="$2"
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
        --source-path)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Architecture switching script for Open Saves AWS"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --from-arch ARCH             Current architecture (amd64|arm64, auto-detected if not specified)"
            echo "  --to-arch ARCH               Target architecture (amd64|arm64, required)"
            echo "  --namespace NAMESPACE        Kubernetes namespace (default: open-saves)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --source-path PATH           Path to source code (default: /home/ec2-user/projects/open-saves-aws/aws)"
            echo "  --help                       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --to-arch arm64                   # Switch to ARM64 (auto-detect current)"
            echo "  $0 --from-arch amd64 --to-arch arm64 # Explicitly switch from AMD64 to ARM64"
            echo ""
            echo "Note: This script only switches Steps 3, 4, and 5. Steps 1 and 2 remain unchanged."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$TO_ARCH" ]; then
    print_error "Target architecture (--to-arch) is required"
    exit 1
fi

if [[ "$TO_ARCH" != "amd64" && "$TO_ARCH" != "arm64" ]]; then
    print_error "Target architecture must be 'amd64' or 'arm64'"
    exit 1
fi

# Auto-detect current architecture if not specified
if [ -z "$FROM_ARCH" ]; then
    print_status "Auto-detecting current architecture..."
    FROM_ARCH=$(detect_current_architecture)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    print_status "Detected current architecture: $FROM_ARCH"
fi

if [[ "$FROM_ARCH" != "amd64" && "$FROM_ARCH" != "arm64" ]]; then
    print_error "Source architecture must be 'amd64' or 'arm64'"
    exit 1
fi

# Check if switching is necessary
if [ "$FROM_ARCH" = "$TO_ARCH" ]; then
    print_warning "Current architecture ($FROM_ARCH) is the same as target architecture ($TO_ARCH)"
    print_status "No switching necessary"
    exit 0
fi

# Main switching logic
main() {
    print_status "Starting architecture switch: $FROM_ARCH → $TO_ARCH"
    
    check_prerequisites
    
    echo ""
    echo "=========================================="
    echo "ARCHITECTURE SWITCH SUMMARY"
    echo "=========================================="
    echo "Region: $REGION"
    echo "From Architecture: $FROM_ARCH"
    echo "To Architecture: $TO_ARCH"
    echo "Namespace: $NAMESPACE"
    echo "Environment: $ENVIRONMENT"
    echo "Source Path: $SOURCE_PATH"
    echo ""
    echo "Steps to be executed:"
    echo "  1. Teardown Step 5 (CloudFront/WAF) for $FROM_ARCH"
    echo "  2. Teardown Step 4 (Compute/App) for $FROM_ARCH"
    echo "  3. Teardown Step 3 (Container Images) for $FROM_ARCH"
    echo "  4. Deploy Step 3 (Container Images) for $TO_ARCH"
    echo "  5. Deploy Step 4 (Compute/App) for $TO_ARCH"
    echo "  6. Deploy Step 5 (CloudFront/WAF) for $TO_ARCH"
    echo ""
    print_warning "This will cause temporary downtime during the switch"
    echo ""
    
    read -p "Proceed with architecture switch? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Architecture switch cancelled by user"
        exit 0
    fi
    
    local start_time=$(date +%s)
    
    # Phase 1: Teardown current architecture (reverse order)
    print_status "Phase 1: Tearing down $FROM_ARCH architecture..."
    
    print_status "Tearing down Step 5 (CloudFront/WAF) for $FROM_ARCH..."
    if ! "$SCRIPT_DIR/teardown-step5.sh" \
        --region "$REGION" \
        --architecture "$FROM_ARCH" \
        --environment "$ENVIRONMENT"; then
        print_error "Failed to teardown Step 5 for $FROM_ARCH"
        exit 1
    fi
    
    print_status "Tearing down Step 4 (Compute/App) for $FROM_ARCH..."
    if ! "$SCRIPT_DIR/teardown-step4.sh" \
        --region "$REGION" \
        --architecture "$FROM_ARCH" \
        --namespace "$NAMESPACE" \
        --environment "$ENVIRONMENT"; then
        print_error "Failed to teardown Step 4 for $FROM_ARCH"
        exit 1
    fi
    
    print_status "Tearing down Step 3 (Container Images) for $FROM_ARCH..."
    if ! "$SCRIPT_DIR/teardown-step3.sh" \
        --region "$REGION" \
        --architecture "$FROM_ARCH" \
        --environment "$ENVIRONMENT" \
        --delete-images; then
        print_error "Failed to teardown Step 3 for $FROM_ARCH"
        exit 1
    fi
    
    print_success "Phase 1 completed: $FROM_ARCH architecture torn down"
    
    # Phase 2: Deploy new architecture
    print_status "Phase 2: Deploying $TO_ARCH architecture..."
    
    print_status "Deploying Step 3 (Container Images) for $TO_ARCH..."
    if ! "$SCRIPT_DIR/deploy-step3.sh" \
        --region "$REGION" \
        --architecture "$TO_ARCH" \
        --source-path "$SOURCE_PATH" \
        --environment "$ENVIRONMENT"; then
        print_error "Failed to deploy Step 3 for $TO_ARCH"
        exit 1
    fi
    
    print_status "Deploying Step 4 (Compute/App) for $TO_ARCH..."
    if ! "$SCRIPT_DIR/deploy-step4.sh" \
        --region "$REGION" \
        --architecture "$TO_ARCH" \
        --namespace "$NAMESPACE" \
        --environment "$ENVIRONMENT"; then
        print_error "Failed to deploy Step 4 for $TO_ARCH"
        exit 1
    fi
    
    print_status "Deploying Step 5 (CloudFront/WAF) for $TO_ARCH..."
    if ! "$SCRIPT_DIR/deploy-step5.sh" \
        --region "$REGION" \
        --architecture "$TO_ARCH" \
        --environment "$ENVIRONMENT"; then
        print_error "Failed to deploy Step 5 for $TO_ARCH"
        exit 1
    fi
    
    print_success "Phase 2 completed: $TO_ARCH architecture deployed"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "=========================================="
    echo "ARCHITECTURE SWITCH COMPLETE"
    echo "=========================================="
    echo "Switched from: $FROM_ARCH"
    echo "Switched to: $TO_ARCH"
    echo "Total Duration: $((duration / 60)) minutes $((duration % 60)) seconds"
    echo ""
    
    # Display new endpoints
    print_status "New application endpoints:"
    
    # Get load balancer hostname
    if LB_HOSTNAME=$(aws ssm get-parameter --name "/open-saves/step4/load_balancer_hostname_${TO_ARCH}" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
        echo "  Direct Load Balancer:"
        echo "    HTTP API: http://$LB_HOSTNAME:8080"
        echo "    gRPC API: $LB_HOSTNAME:8081"
    fi
    
    # Get CloudFront domain
    if CF_DOMAIN=$(aws ssm get-parameter --name "/open-saves/step5/cloudfront_domain_name_${TO_ARCH}" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
        echo "  CloudFront CDN:"
        echo "    HTTPS API: https://$CF_DOMAIN"
    fi
    
    echo ""
    print_success "Architecture switch completed successfully!"
    print_status "The application is now running on $TO_ARCH architecture"
}

# Execute main function
main "$@"
