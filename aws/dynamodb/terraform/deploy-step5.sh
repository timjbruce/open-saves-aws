#!/bin/bash

# Deploy Step 5: CloudFront and WAF
# This step creates CloudFront distribution and WAF for enhanced security and performance

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

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" ]]; then
    echo "Error: Architecture must be 'amd64' or 'arm64'"
    exit 1
fi

echo "=========================================="
echo "Deploying Step 5: CloudFront and WAF"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Environment: $ENVIRONMENT"
echo ""

# Verify prerequisites
echo "Verifying prerequisites..."
REQUIRED_PARAMS=(
    "/open-saves/step1/vpc_id"
    "/open-saves/step4/load_balancer_hostname_${ARCHITECTURE}"
    "/open-saves/step4/service_account_role_arn_${ARCHITECTURE}"
)

for param in "${REQUIRED_PARAMS[@]}"; do
    if ! aws ssm get-parameter --name "$param" --region "$REGION" >/dev/null 2>&1; then
        echo "Error: Required parameter not found: $param"
        echo "Please ensure previous steps are completed:"
        echo "  - Step 1: deploy-step1.sh"
        echo "  - Step 4: deploy-step4.sh --architecture $ARCHITECTURE"
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
    -var="environment=$ENVIRONMENT" \
    -out=tfplan

# Apply the deployment
echo "Applying Terraform deployment..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Get CloudFront domain name
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)

echo ""
echo "=========================================="
echo "Step 5 deployment completed successfully!"
echo "=========================================="
echo ""
echo "Resources created:"
echo "- CloudFront distribution"
echo "- WAF Web ACLs (regional and CloudFront)"
echo "- Security groups for CloudFront access"
echo "- CloudWatch dashboard for monitoring"
echo ""
echo "CloudFront endpoints:"
echo "- HTTPS API: https://$CLOUDFRONT_DOMAIN"
echo "- Distribution ID: $DISTRIBUTION_ID"
echo ""
echo "Security features:"
echo "- DDoS protection via AWS Shield"
echo "- Rate limiting via WAF"
echo "- SQL injection protection"
echo "- Geographic restrictions (configurable)"
echo ""
echo "Monitoring:"
echo "- CloudWatch dashboard: OpenSaves-Security-$ARCHITECTURE"
echo "- WAF logs: /aws/waf/open-saves-$ARCHITECTURE"
echo ""
echo "Configuration stored in SSM Parameter Store under /open-saves/step5/"
echo ""
echo "Note: CloudFront distribution may take 15-20 minutes to fully deploy globally."
echo "You can check the status in the AWS Console or with:"
echo "aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status'"
