#!/bin/bash

# Teardown Step 2: Data Infrastructure
# This step destroys DocumentDB cluster, S3 bucket, and ElastiCache Redis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/step2-infrastructure"

# Default values
REGION="us-east-1"
ARCHITECTURE="amd64"
ENVIRONMENT="dev"
EMPTY_S3="false"

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
        --empty-s3)
            EMPTY_S3="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --region REGION              AWS region (default: us-east-1)"
            echo "  --architecture ARCH          Architecture identifier (amd64|arm64, default: amd64)"
            echo "  --environment ENV            Environment name (default: dev)"
            echo "  --empty-s3                   Empty S3 bucket before destroying"
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
echo "Tearing down Step 2: Data Infrastructure"
echo "=========================================="
echo "Region: $REGION"
echo "Architecture: $ARCHITECTURE"
echo "Environment: $ENVIRONMENT"
echo "Empty S3: $EMPTY_S3"
echo ""

# Change to step directory
cd "$STEP_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    echo "No Terraform state found. Step 2 may not be deployed or already destroyed."
    
    # Still try to empty S3 if requested
    if [ "$EMPTY_S3" = "true" ]; then
        echo "Attempting to empty S3 bucket..."
        
        # Get S3 bucket name from SSM if available
        if S3_BUCKET_NAME=$(aws ssm get-parameter --name "/open-saves/step2/s3_bucket_name" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
            echo "Emptying S3 bucket: $S3_BUCKET_NAME"
            aws s3 rm "s3://$S3_BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
        fi
    fi
    
    exit 0
fi

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Empty S3 bucket if requested
if [ "$EMPTY_S3" = "true" ]; then
    echo "Emptying S3 bucket before destruction..."
    
    # Get S3 bucket name from SSM
    if S3_BUCKET_NAME=$(aws ssm get-parameter --name "/open-saves/step2/s3_bucket_name" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null); then
        echo "Emptying S3 bucket: $S3_BUCKET_NAME"
        aws s3 rm "s3://$S3_BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
    else
        echo "Warning: Could not retrieve S3 bucket name from SSM Parameter Store"
        echo "You may need to manually empty the S3 bucket if it exists"
    fi
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
aws ssm delete-parameter --name "/open-saves/step2/documentdb_endpoint" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/documentdb_port" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/documentdb_username" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/documentdb_password_secret_arn" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/s3_bucket_arn" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/s3_bucket_id" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/s3_bucket_name" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/redis_endpoint" --region "$REGION" 2>/dev/null || true
aws ssm delete-parameter --name "/open-saves/step2/redis_port" --region "$REGION" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Step 2 teardown completed successfully!"
echo "=========================================="
echo ""
echo "Resources destroyed:"
echo "- DocumentDB cluster and instances"
echo "- S3 bucket for blob storage"
if [ "$EMPTY_S3" = "true" ]; then
    echo "- S3 bucket contents (emptied)"
fi
echo "- ElastiCache Redis cluster"
echo "- Security groups and subnet groups"
echo "- SSM parameters and configuration"
