#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Image Rebuild ===${NC}"

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
NAMESPACE="open-saves"

# Ask for architecture
echo -e "${YELLOW}Which architecture would you like to rebuild?${NC}"
echo -e "1. AMD64 (x86_64)"
echo -e "2. ARM64 (aarch64)"
echo -e "3. Both (multi-architecture)"
read -p "Enter your choice (1-3): " arch_choice

case $arch_choice in
  1) ARCH="amd64" ;;
  2) ARCH="arm64" ;;
  3) ARCH="both" ;;
  *) 
    echo -e "${RED}Invalid choice. Defaulting to AMD64.${NC}"
    ARCH="amd64"
    ;;
esac

# Function to build and push image for a specific architecture
build_and_push() {
  local arch=$1
  echo -e "${YELLOW}=== Rebuilding Open Saves AWS ${arch} Image ===${NC}"
  
  # Get ECR repository URI
  ECR_REPO_URI="$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION 2>/dev/null || echo "")"
  
  if [ -z "$ECR_REPO_URI" ]; then
    echo -e "${RED}ECR repository not found. Creating...${NC}"
    aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
    ECR_REPO_URI="$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION)"
  fi
  
  echo -e "${GREEN}ECR repository URI: ${ECR_REPO_URI}${NC}"
  
  # Build the application
  echo -e "${YELLOW}Building Open Saves AWS adapter for ${arch}...${NC}"
  GOOS=linux GOARCH=$arch CGO_ENABLED=0 go build -o open-saves-aws-$arch .
  echo -e "${GREEN}Application built successfully.${NC}"
  
  # Build Docker image
  echo -e "${YELLOW}Building Docker image for ${arch}...${NC}"
  docker build --build-arg TARGETARCH=$arch -t $ECR_REPO_NAME:$arch .
  echo -e "${GREEN}Docker image built successfully.${NC}"
  
  # Push Docker image to ECR
  echo -e "${YELLOW}Pushing Docker image to ECR...${NC}"
  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
  docker tag $ECR_REPO_NAME:$arch $ECR_REPO_URI:$arch
  
  # If this is AMD64, also tag as latest
  if [ "$arch" == "amd64" ]; then
    docker tag $ECR_REPO_NAME:$arch $ECR_REPO_URI:latest
    docker push $ECR_REPO_URI:latest
  fi
  
  docker push $ECR_REPO_URI:$arch
  echo -e "${GREEN}Docker image pushed to ECR.${NC}"
}

# Build and push images based on selected architecture
if [ "$ARCH" == "both" ]; then
  build_and_push "amd64"
  build_and_push "arm64"
else
  build_and_push "$ARCH"
fi

# Ask if user wants to restart the deployment
echo -e "${YELLOW}Do you want to restart the deployment?${NC}"
read -p "Enter y/n: " restart_choice

if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
  # Restart the deployment
  echo -e "${YELLOW}Restarting the deployment...${NC}"
  kubectl rollout restart deployment/open-saves -n $NAMESPACE
  echo -e "${GREEN}Deployment restarted.${NC}"
  
  echo -e "${YELLOW}Waiting for deployment to be ready...${NC}"
  kubectl rollout status deployment/open-saves -n $NAMESPACE --timeout=300s || true
fi

echo -e "${GREEN}Rebuild process complete!${NC}"
