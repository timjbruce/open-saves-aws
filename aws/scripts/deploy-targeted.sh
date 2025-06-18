#!/bin/bash

# deploy-targeted.sh - Script to deploy Open Saves AWS infrastructure in discrete steps
# This script allows deploying each Terraform module separately

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
ARCHITECTURE="amd64"
ENVIRONMENT="dev"
ACTION="apply"
TERRAFORM_DIR="/home/ec2-user/projects/open-saves-aws/aws/terraform"
STEP=""
SOURCE_HASH=$(date +%s) # Default source hash for container builds

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --arch|--architecture)
      ARCHITECTURE="$2"
      shift 2
      ;;
    --env|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --step)
      STEP="$2"
      shift 2
      ;;
    --destroy)
      ACTION="destroy"
      shift
      ;;
    --source-hash)
      SOURCE_HASH="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --arch, --architecture ARCH   Set the architecture (amd64, arm64, both)"
      echo "  --env, --environment ENV      Set the environment (dev, prod)"
      echo "  --step STEP                   Specify which step to deploy:"
      echo "                                  1: EKS cluster and ECR registry"
      echo "                                  2: Infrastructure (DynamoDB, S3, Redis)"
      echo "                                  3: Container images"
      echo "                                  4: Compute nodes and application"
      echo "                                  all: All steps in sequence"
      echo "  --destroy                     Destroy the infrastructure instead of deploying"
      echo "  --source-hash HASH            Source hash for container builds (default: timestamp)"
      echo "  --help                        Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate architecture
if [[ "$ARCHITECTURE" != "amd64" && "$ARCHITECTURE" != "arm64" && "$ARCHITECTURE" != "both" ]]; then
  echo -e "${RED}Error: Architecture must be one of: amd64, arm64, both${NC}"
  exit 1
fi

# Validate step
if [[ -z "$STEP" ]]; then
  echo -e "${RED}Error: Step must be specified with --step${NC}"
  echo "Available steps:"
  echo "  1: EKS cluster and ECR registry"
  echo "  2: Infrastructure (DynamoDB, S3, Redis)"
  echo "  3: Container images"
  echo "  4: Compute nodes and application"
  echo "  all: All steps in sequence"
  exit 1
fi

# Print deployment information
echo -e "${YELLOW}=== Open Saves AWS Targeted Deployment ===${NC}"
echo -e "${YELLOW}Architecture: $ARCHITECTURE${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Action: $ACTION${NC}"
echo -e "${YELLOW}Step: $STEP${NC}"
echo -e "${YELLOW}=======================================${NC}"

# Change to the terraform directory
cd "$TERRAFORM_DIR"

# Run terraform init if needed
if [ ! -d ".terraform" ]; then
  echo -e "${YELLOW}Initializing Terraform...${NC}"
  terraform init
fi

# Function to apply or destroy a specific module
deploy_module() {
  local module=$1
  local module_name=$2
  
  echo -e "${YELLOW}$ACTION module: $module_name${NC}"
  
  if [ "$ACTION" == "apply" ]; then
    terraform apply \
      -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
      -var="architecture=$ARCHITECTURE" \
      -var="source_hash=$SOURCE_HASH" \
      -target="module.$module" \
      -auto-approve
  elif [ "$ACTION" == "destroy" ]; then
    terraform destroy \
      -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
      -var="architecture=$ARCHITECTURE" \
      -var="source_hash=$SOURCE_HASH" \
      -target="module.$module" \
      -auto-approve
  fi
  
  echo -e "${GREEN}Module $module_name $ACTION completed successfully!${NC}"
}

# Execute the specified step
case $STEP in
  1)
    echo -e "${YELLOW}Step 1: Creating EKS cluster and ECR registry${NC}"
    deploy_module "step1_cluster_ecr" "EKS cluster and ECR registry"
    ;;
  2)
    echo -e "${YELLOW}Step 2: Deploying infrastructure (DynamoDB, S3, Redis)${NC}"
    deploy_module "step2_infrastructure" "Infrastructure (DynamoDB, S3, Redis)"
    
    # Update configuration files with actual values
    echo -e "${YELLOW}Updating configuration files with actual values...${NC}"
    /home/ec2-user/projects/open-saves-aws/aws/scripts/update-config.sh --config-dir "/home/ec2-user/projects/open-saves-aws/aws/config" --region "${REGION:-us-west-2}" --terraform-dir "$TERRAFORM_DIR"
    ;;
  3)
    echo -e "${YELLOW}Step 3: Building and pushing container images${NC}"
    deploy_module "step3_container_images" "Container images"
    ;;
  4)
    echo -e "${YELLOW}Step 4: Deploying compute nodes and application${NC}"
    deploy_module "step4_compute_app" "Compute nodes and application"
    ;;
  all)
    echo -e "${YELLOW}Executing all steps in sequence${NC}"
    
    if [ "$ACTION" == "apply" ]; then
      echo -e "${YELLOW}Step 1: Creating EKS cluster and ECR registry${NC}"
      deploy_module "step1_cluster_ecr" "EKS cluster and ECR registry"
      
      echo -e "${YELLOW}Step 2: Deploying infrastructure (DynamoDB, S3, Redis)${NC}"
      deploy_module "step2_infrastructure" "Infrastructure (DynamoDB, S3, Redis)"
      
      # Update configuration files with actual values
      echo -e "${YELLOW}Updating configuration files with actual values...${NC}"
      /home/ec2-user/projects/open-saves-aws/aws/scripts/update-config.sh --config-dir "/home/ec2-user/projects/open-saves-aws/aws/config" --region "${REGION:-us-west-2}" --terraform-dir "$TERRAFORM_DIR"
      
      echo -e "${YELLOW}Step 3: Building and pushing container images${NC}"
      deploy_module "step3_container_images" "Container images"
      
      echo -e "${YELLOW}Step 4: Deploying compute nodes and application${NC}"
      deploy_module "step4_compute_app" "Compute nodes and application"
    elif [ "$ACTION" == "destroy" ]; then
      # Destroy in reverse order
      echo -e "${YELLOW}Step 4: Destroying compute nodes and application${NC}"
      deploy_module "step4_compute_app" "Compute nodes and application"
      
      echo -e "${YELLOW}Step 3: Destroying container images${NC}"
      deploy_module "step3_container_images" "Container images"
      
      echo -e "${YELLOW}Step 2: Destroying infrastructure (DynamoDB, S3, Redis)${NC}"
      deploy_module "step2_infrastructure" "Infrastructure (DynamoDB, S3, Redis)"
      
      echo -e "${YELLOW}Step 1: Destroying EKS cluster and ECR registry${NC}"
      deploy_module "step1_cluster_ecr" "EKS cluster and ECR registry"
    fi
    ;;
  *)
    echo -e "${RED}Error: Invalid step specified: $STEP${NC}"
    echo "Available steps:"
    echo "  1: EKS cluster and ECR registry"
    echo "  2: Infrastructure (DynamoDB, S3, Redis)"
    echo "  3: Container images"
    echo "  4: Compute nodes and application"
    echo "  all: All steps in sequence"
    exit 1
    ;;
esac

echo -e "${GREEN}Operation completed successfully!${NC}"

# Display helpful information after deployment
if [ "$ACTION" == "apply" ]; then
  if [ "$STEP" == "4" ] || [ "$STEP" == "all" ]; then
    echo -e "${YELLOW}To access your Open Saves deployment:${NC}"
    echo -e "1. Configure kubectl: ${GREEN}aws eks update-kubeconfig --name open-saves-cluster-new --region us-west-2${NC}"
    echo -e "2. Check pods: ${GREEN}kubectl get pods -n open-saves${NC}"
    echo -e "3. Get service URL: ${GREEN}kubectl get service -n open-saves${NC}"
    echo -e "4. Run tests: ${GREEN}cd /home/ec2-user/projects/open-saves-aws/aws && ./open-saves-test.sh http://\$SERVICE_URL:8080${NC}"
  fi
fi
