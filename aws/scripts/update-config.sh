#!/bin/bash

# update-config.sh - Script to update configuration files with actual values
# This script ensures that both config.yaml and config.json are properly updated
# with actual values for S3 bucket, server ports, ElastiCache Redis endpoint, and ECR repository

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CONFIG_DIR="/home/ec2-user/projects/open-saves-aws/aws/config"
REGION="us-west-2"
TERRAFORM_DIR="/home/ec2-user/projects/open-saves-aws/aws/terraform"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --config-dir)
      CONFIG_DIR="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --config-dir DIR      Directory containing config files (default: /home/ec2-user/projects/open-saves-aws/aws/config)"
      echo "  --region REGION       AWS region (default: us-west-2)"
      echo "  --terraform-dir DIR   Directory containing Terraform files (default: /home/ec2-user/projects/open-saves-aws/aws/terraform)"
      echo "  --help                Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo -e "${YELLOW}=== Updating Configuration Files ===${NC}"
echo -e "${YELLOW}Config directory: ${CONFIG_DIR}${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"

# Create config directory if it doesn't exist
mkdir -p ${CONFIG_DIR}

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${YELLOW}Account ID: ${ACCOUNT_ID}${NC}"

# Get S3 bucket name
S3_BUCKET="open-saves-blobs-${ACCOUNT_ID}"
echo -e "${YELLOW}S3 bucket: ${S3_BUCKET}${NC}"

# Get ECR repository URI
ECR_REPO_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/dev-open-saves"
echo -e "${YELLOW}ECR repository URI: ${ECR_REPO_URI}${NC}"

# Get Redis endpoint from SSM Parameter Store
echo -e "${YELLOW}Getting Redis endpoint from SSM Parameter Store...${NC}"
CONFIG_JSON=$(aws ssm get-parameter --name "/etc/open-saves/config.yaml" --region ${REGION} --query "Parameter.Value" --output text)

# Parse the Redis endpoint from the JSON
if [[ $CONFIG_JSON == *"elasticache"* ]]; then
  # Try to extract using jq if available
  if command -v jq &> /dev/null; then
    REDIS_ENDPOINT=$(echo $CONFIG_JSON | jq -r '.aws.elasticache.address' 2>/dev/null)
  fi
  
  # If jq failed or is not available, try with grep and sed
  if [ -z "$REDIS_ENDPOINT" ] || [ "$REDIS_ENDPOINT" == "null" ]; then
    REDIS_ENDPOINT=$(echo $CONFIG_JSON | grep -o '"address":[^,}]*' | sed 's/"address"://; s/"//g')
  fi
fi

# If we still don't have a valid Redis endpoint, get it from kubectl
if [ -z "$REDIS_ENDPOINT" ] || [ "$REDIS_ENDPOINT" == "null" ] || [[ $REDIS_ENDPOINT == *"[redis-endpoint]"* ]]; then
  echo -e "${YELLOW}Getting Redis endpoint from Kubernetes ConfigMap...${NC}"
  if kubectl get configmap open-saves-config -n open-saves &>/dev/null; then
    REDIS_ENDPOINT=$(kubectl get configmap open-saves-config -n open-saves -o jsonpath='{.data.config\.yaml}' | grep -o 'address: "[^"]*' | sed 's/address: "//g')
  fi
fi

# If we still don't have a valid Redis endpoint, use the output from Terraform
if [ -z "$REDIS_ENDPOINT" ] || [ "$REDIS_ENDPOINT" == "null" ] || [[ $REDIS_ENDPOINT == *"[redis-endpoint]"* ]]; then
  echo -e "${YELLOW}Getting Redis endpoint from Terraform output...${NC}"
  cd ${TERRAFORM_DIR:-"/home/ec2-user/projects/open-saves-aws/aws/terraform"}
  REDIS_ENDPOINT=$(terraform output -json | jq -r '.redis_endpoint.value')
fi

echo -e "${YELLOW}Redis endpoint: ${REDIS_ENDPOINT}${NC}"

# Create config.yaml file
echo -e "${YELLOW}Creating config.yaml file...${NC}"
cat > ${CONFIG_DIR}/config.yaml <<EOF
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "${REGION}"
  dynamodb:
    stores_table: "open-saves-stores"
    records_table: "open-saves-records"
    metadata_table: "open-saves-metadata"
  s3:
    bucket_name: "${S3_BUCKET}"
  elasticache:
    address: "${REDIS_ENDPOINT}"
    ttl: 3600
  ecr:
    repository_uri: "${ECR_REPO_URI}"
EOF

# Create config.json file
echo -e "${YELLOW}Creating config.json file...${NC}"
python3 -c "import yaml, json, sys; print(json.dumps(yaml.safe_load(open('${CONFIG_DIR}/config.yaml').read())))" > ${CONFIG_DIR}/config.json

echo -e "${GREEN}Configuration files updated successfully!${NC}"
echo -e "${GREEN}config.yaml: ${CONFIG_DIR}/config.yaml${NC}"
echo -e "${GREEN}config.json: ${CONFIG_DIR}/config.json${NC}"
