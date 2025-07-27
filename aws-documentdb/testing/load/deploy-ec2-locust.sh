#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
REGION=$(aws configure get region || echo "us-west-2")
WORKER_COUNT=3
INSTANCE_TYPE="c5.large"
CLOUDFRONT_ENDPOINT=""
CLOUDFRONT_DISTRIBUTION_ID="EV2NR6DUG279M"  # Default ID for Open Saves CloudFront distribution
SCRIPTS_BUCKET=""
TARGET_ADDRESS=""  # New parameter for target address
ALLOWED_IP="0.0.0.0/0"  # Default to allow all IPs

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --region)
      REGION="$2"
      shift
      shift
      ;;
    --worker-count)
      WORKER_COUNT="$2"
      shift
      shift
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift
      shift
      ;;
    --endpoint)
      CLOUDFRONT_ENDPOINT="$2"
      shift
      shift
      ;;
    --distribution-id)
      CLOUDFRONT_DISTRIBUTION_ID="$2"
      shift
      shift
      ;;
    --scripts-bucket)
      SCRIPTS_BUCKET="$2"
      shift
      shift
      ;;
    --address)
      TARGET_ADDRESS="$2"
      shift
      shift
      ;;
    --allowed-ip)
      ALLOWED_IP="$2"
      shift
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --region REGION          AWS region to deploy to (default: from AWS config or us-west-2)"
      echo "  --worker-count COUNT     Number of Locust worker instances (default: 3)"
      echo "  --instance-type TYPE     EC2 instance type for workers (default: c5.large)"
      echo "  --endpoint ENDPOINT      CloudFront endpoint for Open Saves (required)"
      echo "  --distribution-id ID     CloudFront distribution ID (default: EV2NR6DUG279M)"
      echo "  --scripts-bucket BUCKET  S3 bucket name containing Locust scripts (required)"
      echo "  --address ADDRESS        Target address for load testing (optional, defaults to CloudFront endpoint)"
      echo "  --allowed-ip IP/CIDR     IP address or CIDR block allowed to access Locust web UI and SSH (default: 0.0.0.0/0)"
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

# Check if CloudFront endpoint is provided
if [ -z "$CLOUDFRONT_ENDPOINT" ]; then
  echo -e "${RED}Error: CloudFront endpoint is required. Use --endpoint parameter.${NC}"
  echo -e "${YELLOW}Example: $0 --endpoint dlwqqp0bucqw2.cloudfront.net --scripts-bucket my-locust-scripts${NC}"
  exit 1
fi

# Check if scripts bucket is provided
if [ -z "$SCRIPTS_BUCKET" ]; then
  echo -e "${RED}Error: S3 bucket name is required. Use --scripts-bucket parameter.${NC}"
  echo -e "${YELLOW}Example: $0 --endpoint dlwqqp0bucqw2.cloudfront.net --scripts-bucket my-locust-scripts${NC}"
  exit 1
fi

# Set target address to CloudFront endpoint if not provided
if [ -z "$TARGET_ADDRESS" ]; then
  # Ensure CloudFront endpoint has https:// prefix
  if [[ ! "$CLOUDFRONT_ENDPOINT" =~ ^https?:// ]]; then
    TARGET_ADDRESS="https://$CLOUDFRONT_ENDPOINT"
  else
    TARGET_ADDRESS="$CLOUDFRONT_ENDPOINT"
  fi
else
  # Ensure target address has http:// or https:// prefix
  if [[ ! "$TARGET_ADDRESS" =~ ^https?:// ]]; then
    TARGET_ADDRESS="https://$TARGET_ADDRESS"
  fi
fi

echo -e "${YELLOW}Creating terraform.tfvars file...${NC}"
cd $(dirname $0)/terraform/ec2_locust

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
region = "$REGION"
open_saves_endpoint = "$TARGET_ADDRESS"
worker_count = $WORKER_COUNT
locust_instance_type = "$INSTANCE_TYPE"
cloudfront_distribution_id = "$CLOUDFRONT_DISTRIBUTION_ID"
scripts_bucket = "$SCRIPTS_BUCKET"
allowed_ip = "$ALLOWED_IP"
EOF

echo -e "${GREEN}Created terraform.tfvars file${NC}"

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Plan Terraform deployment
echo -e "${YELLOW}Planning Terraform deployment...${NC}"
terraform plan -out=tfplan

# Apply Terraform configuration
echo -e "${YELLOW}Deploying Locust EC2 infrastructure...${NC}"
terraform apply -auto-approve tfplan

# Get the Locust web UI URL
LOCUST_URL=$(terraform output -raw locust_web_ui)

echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${YELLOW}Locust web UI:${NC} $LOCUST_URL"
echo -e "${YELLOW}CloudWatch dashboard:${NC} $(terraform output -raw cloudwatch_dashboard_url)"
echo ""
echo -e "${YELLOW}Note: It may take a few minutes for the Locust master to start and the web UI to become available.${NC}"
echo -e "${YELLOW}You can check the status by viewing the CloudWatch logs.${NC}"
