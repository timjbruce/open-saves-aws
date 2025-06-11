#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Step-by-Step Teardown Script ===${NC}"
echo -e "${YELLOW}This script allows tearing down Open Saves for AWS in discrete steps${NC}"

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
CLUSTER_NAME="open-saves-cluster-new"
NAMESPACE="open-saves"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"
REDIS_CLUSTER="open-saves-cache"

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
  echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
  exit 1
fi
echo -e "${GREEN}AWS credentials verified.${NC}"

# Function to remove Kubernetes resources
remove_kubernetes_resources() {
  echo -e "${YELLOW}Step 1: Removing Kubernetes resources${NC}"
  
  # Check if namespace exists
  if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Deleting namespace $NAMESPACE...${NC}"
    kubectl delete namespace $NAMESPACE
    echo -e "${GREEN}Kubernetes resources deleted.${NC}"
  else
    echo -e "${GREEN}Namespace $NAMESPACE does not exist. Skipping.${NC}"
  fi
  
  echo -e "${GREEN}Step 1 completed successfully!${NC}"
}

# Function to remove compute nodes
remove_compute_nodes() {
  echo -e "${YELLOW}Step 2: Removing compute nodes${NC}"
  
  # Check if EKS cluster exists
  if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    # Check for ARM64 node group
    if aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name arm64-nodes --region $AWS_REGION &> /dev/null; then
      echo -e "${YELLOW}Deleting ARM64 node group...${NC}"
      eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=arm64-nodes --region $AWS_REGION
      echo -e "${GREEN}ARM64 node group deleted.${NC}"
    else
      echo -e "${GREEN}ARM64 node group does not exist. Skipping.${NC}"
    fi
    
    # Check for AMD64 node group
    if aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name amd64-nodes --region $AWS_REGION &> /dev/null; then
      echo -e "${YELLOW}Deleting AMD64 node group...${NC}"
      eksctl delete nodegroup --cluster=$CLUSTER_NAME --name=amd64-nodes --region $AWS_REGION
      echo -e "${GREEN}AMD64 node group deleted.${NC}"
    else
      echo -e "${GREEN}AMD64 node group does not exist. Skipping.${NC}"
    fi
  else
    echo -e "${GREEN}EKS cluster does not exist. Skipping node group deletion.${NC}"
  fi
  
  echo -e "${GREEN}Step 2 completed successfully!${NC}"
}

# Function to remove Redis cluster
remove_redis_cluster() {
  echo -e "${YELLOW}Step 3: Removing ElastiCache Redis cluster${NC}"
  
  # Check if Redis cluster exists
  if aws elasticache describe-cache-clusters --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Deleting Redis cluster...${NC}"
    aws elasticache delete-cache-cluster --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
    
    echo -e "${YELLOW}Waiting for Redis cluster to be deleted...${NC}"
    aws elasticache wait cache-cluster-deleted --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
    echo -e "${GREEN}Redis cluster deleted.${NC}"
  else
    echo -e "${GREEN}Redis cluster does not exist. Skipping.${NC}"
  fi
  
  # Check if subnet group exists
  if aws elasticache describe-cache-subnet-groups --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Deleting ElastiCache subnet group...${NC}"
    aws elasticache delete-cache-subnet-group --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION
    echo -e "${GREEN}ElastiCache subnet group deleted.${NC}"
  else
    echo -e "${GREEN}ElastiCache subnet group does not exist. Skipping.${NC}"
  fi
  
  echo -e "${GREEN}Step 3 completed successfully!${NC}"
}

# Function to remove DynamoDB tables and S3 bucket
remove_dynamodb_s3() {
  echo -e "${YELLOW}Step 4: Removing DynamoDB tables and S3 bucket${NC}"
  
  # Delete DynamoDB tables
  for table in open-saves-stores open-saves-records open-saves-metadata; do
    if aws dynamodb describe-table --table-name $table --region $AWS_REGION &> /dev/null; then
      echo -e "${YELLOW}Deleting DynamoDB table $table...${NC}"
      aws dynamodb delete-table --table-name $table --region $AWS_REGION
      
      echo -e "${YELLOW}Waiting for table $table to be deleted...${NC}"
      aws dynamodb wait table-not-exists --table-name $table --region $AWS_REGION
      echo -e "${GREEN}Table $table deleted.${NC}"
    else
      echo -e "${GREEN}Table $table does not exist. Skipping.${NC}"
    fi
  done
  
  # Delete S3 bucket
  if aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
    echo -e "${YELLOW}Emptying S3 bucket...${NC}"
    aws s3 rm s3://$S3_BUCKET --recursive
    
    echo -e "${YELLOW}Deleting S3 bucket...${NC}"
    aws s3api delete-bucket --bucket $S3_BUCKET --region $AWS_REGION
    echo -e "${GREEN}S3 bucket deleted.${NC}"
  else
    echo -e "${GREEN}S3 bucket does not exist. Skipping.${NC}"
  fi
  
  echo -e "${GREEN}Step 4 completed successfully!${NC}"
}

# Function to remove ECR repository
remove_ecr_repository() {
  echo -e "${YELLOW}Step 5: Removing ECR repository${NC}"
  
  # Check if ECR repository exists
  if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Deleting ECR repository...${NC}"
    aws ecr delete-repository --repository-name $ECR_REPO_NAME --force --region $AWS_REGION
    echo -e "${GREEN}ECR repository deleted.${NC}"
  else
    echo -e "${GREEN}ECR repository does not exist. Skipping.${NC}"
  fi
  
  echo -e "${GREEN}Step 5 completed successfully!${NC}"
}

# Function to remove EKS cluster
remove_eks_cluster() {
  echo -e "${YELLOW}Step 6: Removing EKS cluster${NC}"
  
  # Check if EKS cluster exists
  if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Deleting EKS cluster...${NC}"
    eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
    echo -e "${GREEN}EKS cluster deleted.${NC}"
  else
    echo -e "${GREEN}EKS cluster does not exist. Skipping.${NC}"
  fi
  
  echo -e "${GREEN}Step 6 completed successfully!${NC}"
}

# Main menu
echo -e "${YELLOW}Starting Open Saves AWS teardown...${NC}"
echo -e "${YELLOW}Please select a step to execute:${NC}"
echo -e "1. Step 1: Remove Kubernetes resources"
echo -e "2. Step 2: Remove compute nodes"
echo -e "3. Step 3: Remove ElastiCache Redis cluster"
echo -e "4. Step 4: Remove DynamoDB tables and S3 bucket"
echo -e "5. Step 5: Remove ECR repository"
echo -e "6. Step 6: Remove EKS cluster"
echo -e "7. Execute all steps in sequence"
echo -e "8. Exit"

read -p "Enter your choice (1-8): " choice

case $choice in
  1)
    remove_kubernetes_resources
    ;;
  2)
    remove_compute_nodes
    ;;
  3)
    remove_redis_cluster
    ;;
  4)
    remove_dynamodb_s3
    ;;
  5)
    remove_ecr_repository
    ;;
  6)
    remove_eks_cluster
    ;;
  7)
    remove_kubernetes_resources
    remove_compute_nodes
    remove_redis_cluster
    remove_dynamodb_s3
    remove_ecr_repository
    remove_eks_cluster
    ;;
  8)
    echo -e "${YELLOW}Exiting.${NC}"
    exit 0
    ;;
  *)
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}=== Open Saves AWS Teardown Step Completed ===${NC}"
