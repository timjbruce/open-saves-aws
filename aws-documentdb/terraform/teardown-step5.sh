#!/bin/bash

# Teardown Step 5: CloudFront and WAF
# This step destroys CloudFront distribution and WAF resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step5-cloudfront-waf"

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
            echo "  --architecture ARCH          Architecture identifier (amd64|arm64, default: amd64)"
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

echo "=========================================="
echo "Tearing down Step 5: CloudFront and WAF"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Environment: $ENVIRONMENT"
echo ""

# Change to step directory
cd "$STEP_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "No Terraform state found. Step 5 may not be deployed or already destroyed."
    exit 0
fi

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Plan the destruction
echo "Planning Terraform destruction..."
terraform plan -destroy \
    -var="region=$REGION" \
    -var="architecture=$ARCHITECTURE" \
    -var="environment=$ENVIRONMENT" \
    -out=destroy.tfplan

# Apply the destruction
echo "Applying Terraform destruction..."
terraform apply destroy.tfplan

# Clean up plan file
rm -f destroy.tfplan

# Clean up SSM parameters
echo "Cleaning up SSM parameters..."
aws ssm delete-parameter --name "/open-saves/step5/cloudfront_domain_name_${ARCHITECTURE}" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step5/cloudfront_distribution_id_${ARCHITECTURE}" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step5/waf_web_acl_arn_${ARCHITECTURE}" --region "$REGION" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Step 5 teardown completed successfully!"
echo "=========================================="
echo ""
echo "Resources destroyed:"
echo "- CloudFront distribution"
echo "- WAF Web ACLs"
echo "- Security groups"
echo "- CloudWatch dashboard"
echo "- SSM parameters"
