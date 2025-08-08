#!/bin/bash

# Deploy Step 2: Data Infrastructure
# This step creates DynamoDB tables, S3 bucket, and ElastiCache Redis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step2-infrastructure"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
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
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture for ElastiCache (amd64|arm64, default: amd64)"
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
echo "Deploying Step 2: Data Infrastructure"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Environment: $ENVIRONMENT"
echo ""

# Verify Step 1 is completed
echo "Verifying Step 1 prerequisites..."
if ! aws ssm get-parameter --name "/open-saves/step1/vpc_id" --region "$REGION" >/dev/null 2>&1; then
    echo "Error: Step 1 must be completed first. VPC ID not found in SSM Parameter Store."
    echo "Please run deploy-step1.sh first."
    exit 1
fi

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
    -var="environment=$ENVIRONMENT" \
    -out=tfplan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

echo ""
echo "=========================================="
echo "Step 2 deployment completed successfully!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "- DynamoDB tables (stores, records, metadata)"
echo "- S3 bucket for blob storage"
echo "- ElastiCache Redis cluster ($ARCHITECTURE)"
echo "- Security groups and subnet groups"
echo "- Configuration in SSM Parameter Store"
echo ""
echo "Configuration stored in SSM Parameter Store under /open-saves/step2/"
echo ""
echo "Next step: Run deploy-step3.sh --architecture $ARCHITECTURE to build container images"
