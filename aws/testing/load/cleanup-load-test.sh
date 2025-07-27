#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REGION=$(aws configure get region || echo "us-west-2")

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --region)
      REGION="$2"
      shift
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --region REGION          AWS region to clean up resources (default: from AWS config or us-west-2)"
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

echo -e "${YELLOW}Starting cleanup of load testing resources in region ${REGION}...${NC}"

# Clean up EC2 Locust resources
if [ -d "$(dirname $0)/terraform/ec2_locust" ]; then
  echo -e "${YELLOW}Cleaning up EC2 Locust resources...${NC}"
  cd "$(dirname $0)/terraform/ec2_locust"
  
  # Check if terraform is initialized
  if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
  fi
  
  # Destroy resources
  echo -e "${YELLOW}Destroying EC2 Locust resources...${NC}"
  terraform destroy -auto-approve
  
  echo -e "${GREEN}EC2 Locust resources cleaned up.${NC}"
  cd - > /dev/null
fi

echo -e "${GREEN}Cleanup completed successfully!${NC}"
