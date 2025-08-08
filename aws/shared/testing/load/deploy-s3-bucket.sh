#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
REGION=$(aws configure get region || echo "us-west-2")
ENVIRONMENT="dev"
SCRIPTS_DIR="$(pwd)/scripts"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --region)
      REGION="$2"
      shift
      shift
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --region REGION          AWS region to deploy to (default: from AWS config or us-west-2)"
      echo "  --environment ENV        Environment name for resource naming (default: dev)"
      echo "  --help                   Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if script files exist
if [ ! -f "$SCRIPTS_DIR/locustfile.py" ] || [ ! -f "$SCRIPTS_DIR/master.sh" ] || [ ! -f "$SCRIPTS_DIR/worker.sh" ]; then
  echo -e "${RED}Error: Required script files not found in $SCRIPTS_DIR${NC}"
  echo -e "${YELLOW}Please ensure locustfile.py, master.sh, and worker.sh exist in the scripts directory.${NC}"
  exit 1
fi

# Navigate to the S3 bucket Terraform directory
cd $(dirname $0)/terraform/s3_bucket

# Create terraform.tfvars file
echo -e "${YELLOW}Creating terraform.tfvars file...${NC}"
cat > terraform.tfvars << EOF
region = "$REGION"
environment = "$ENVIRONMENT"
EOF

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Plan Terraform deployment
echo -e "${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

# Apply Terraform deployment
echo -e "${YELLOW}Deploying S3 bucket...${NC}"
terraform apply -auto-approve tfplan

# Get the bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw bucket_name)

# Upload Locust scripts to S3
echo -e "${YELLOW}Uploading Locust scripts to S3...${NC}"
aws s3 cp $SCRIPTS_DIR/locustfile.py s3://$BUCKET_NAME/locustfile.py
aws s3 cp $SCRIPTS_DIR/master.sh s3://$BUCKET_NAME/master.sh
aws s3 cp $SCRIPTS_DIR/worker.sh s3://$BUCKET_NAME/worker.sh

echo -e "${GREEN}S3 bucket deployed and scripts uploaded successfully!${NC}"
echo -e "${YELLOW}Bucket name:${NC} $BUCKET_NAME"
echo -e "${YELLOW}Use this bucket name when deploying the Locust infrastructure.${NC}"
