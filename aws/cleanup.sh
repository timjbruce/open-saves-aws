#!/bin/bash
# cleanup.sh - Script to clean up all AWS resources created for Open Saves

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Cleanup Script ===${NC}"
echo -e "${YELLOW}This script will remove all AWS resources created for Open Saves${NC}"
echo -e "${RED}WARNING: This will delete all data stored in DynamoDB, S3, and other resources!${NC}"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${GREEN}Cleanup cancelled.${NC}"
    exit 0
fi

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
CLUSTER_NAME="open-saves-cluster"
NAMESPACE="open-saves"
REDIS_CLUSTER="open-saves-cache"
REDIS_CLUSTER_EKS="open-saves-cache-eks"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"

# Step 1: Delete Kubernetes resources
echo -e "${YELLOW}Step 1: Deleting Kubernetes resources...${NC}"
kubectl delete namespace $NAMESPACE || true
echo -e "${GREEN}Kubernetes resources deleted.${NC}"

# Step 2: Delete ElastiCache Redis clusters
echo -e "${YELLOW}Step 2: Deleting ElastiCache Redis clusters...${NC}"
aws elasticache delete-cache-cluster --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION || true
aws elasticache delete-cache-cluster --cache-cluster-id $REDIS_CLUSTER_EKS --region $AWS_REGION || true
echo -e "${YELLOW}Waiting for Redis clusters to be deleted...${NC}"
aws elasticache wait cache-cluster-deleted --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION || true
aws elasticache wait cache-cluster-deleted --cache-cluster-id $REDIS_CLUSTER_EKS --region $AWS_REGION || true

# Delete subnet groups
echo -e "${YELLOW}Deleting ElastiCache subnet groups...${NC}"
aws elasticache delete-cache-subnet-group --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION || true
aws elasticache delete-cache-subnet-group --cache-subnet-group-name open-saves-cache-eks-subnet --region $AWS_REGION || true
echo -e "${GREEN}ElastiCache resources deleted.${NC}"

# Step 3: Delete EKS cluster
echo -e "${YELLOW}Step 3: Deleting EKS cluster...${NC}"
# Delete node group first
aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION || true
echo -e "${YELLOW}Waiting for node group to be deleted (this will take 5-10 minutes)...${NC}"
aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION || true

# Delete cluster
aws eks delete-cluster --name $CLUSTER_NAME --region $AWS_REGION || true
echo -e "${YELLOW}Waiting for EKS cluster to be deleted (this will take 10-15 minutes)...${NC}"
aws eks wait cluster-deleted --name $CLUSTER_NAME --region $AWS_REGION || true
echo -e "${GREEN}EKS cluster deleted.${NC}"

# Step 4: Delete IAM roles
echo -e "${YELLOW}Step 4: Deleting IAM roles...${NC}"
# Detach policies from cluster role
aws iam detach-role-policy --role-name open-saves-eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --region $AWS_REGION || true

# Detach policies from node role
aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --region $AWS_REGION || true
aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --region $AWS_REGION || true
aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --region $AWS_REGION || true
aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess --region $AWS_REGION || true
aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --region $AWS_REGION || true

# Delete roles
aws iam delete-role --role-name open-saves-eks-cluster-role --region $AWS_REGION || true
aws iam delete-role --role-name open-saves-eks-node-role --region $AWS_REGION || true
echo -e "${GREEN}IAM roles deleted.${NC}"

# Step 5: Delete VPC resources
echo -e "${YELLOW}Step 5: Deleting VPC resources...${NC}"
# Get VPC ID from file if it exists
if [ -f .vpc_id ]; then
  VPC_ID=$(cat .vpc_id)
  
  # Delete security groups
  echo -e "${YELLOW}Deleting security groups...${NC}"
  SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].GroupId' --output text --region $AWS_REGION)
  for SG_ID in $SG_IDS; do
    if [ "$SG_ID" != "sg-default" ]; then
      aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION || true
    fi
  done
  
  # Delete subnets
  echo -e "${YELLOW}Deleting subnets...${NC}"
  SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
  for SUBNET_ID in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $AWS_REGION || true
  done
  
  # Delete route tables
  echo -e "${YELLOW}Deleting route tables...${NC}"
  RTB_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[*].RouteTableId' --output text --region $AWS_REGION)
  for RTB_ID in $RTB_IDS; do
    if [[ $RTB_ID != *"rtb-"* ]]; then
      continue
    fi
    # Skip the main route table
    IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids $RTB_ID --query 'RouteTables[0].Associations[?Main==`true`]' --output text --region $AWS_REGION)
    if [ -z "$IS_MAIN" ]; then
      aws ec2 delete-route-table --route-table-id $RTB_ID --region $AWS_REGION || true
    fi
  done
  
  # Detach and delete internet gateway
  echo -e "${YELLOW}Detaching and deleting internet gateway...${NC}"
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text --region $AWS_REGION)
  if [ "$IGW_ID" != "None" ] && [ ! -z "$IGW_ID" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION || true
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION || true
  fi
  
  # Delete VPC
  echo -e "${YELLOW}Deleting VPC...${NC}"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION || true
  
  # Remove VPC ID file
  rm -f .vpc_id
fi
echo -e "${GREEN}VPC resources deleted.${NC}"

# Step 6: Delete DynamoDB tables
echo -e "${YELLOW}Step 6: Deleting DynamoDB tables...${NC}"
aws dynamodb delete-table --table-name open-saves-stores --region $AWS_REGION || true
aws dynamodb delete-table --table-name open-saves-records --region $AWS_REGION || true
aws dynamodb delete-table --table-name open-saves-metadata --region $AWS_REGION || true
echo -e "${YELLOW}Waiting for DynamoDB tables to be deleted...${NC}"
aws dynamodb wait table-not-exists --table-name open-saves-stores --region $AWS_REGION || true
aws dynamodb wait table-not-exists --table-name open-saves-records --region $AWS_REGION || true
aws dynamodb wait table-not-exists --table-name open-saves-metadata --region $AWS_REGION || true
echo -e "${GREEN}DynamoDB tables deleted.${NC}"

# Step 7: Delete S3 bucket
echo -e "${YELLOW}Step 7: Deleting S3 bucket...${NC}"
# Empty the bucket first
aws s3 rm s3://$S3_BUCKET --recursive --region $AWS_REGION || true
# Delete the bucket
aws s3api delete-bucket --bucket $S3_BUCKET --region $AWS_REGION || true
echo -e "${GREEN}S3 bucket deleted.${NC}"

# Step 8: Delete ECR repository
echo -e "${YELLOW}Step 8: Deleting ECR repository...${NC}"
aws ecr delete-repository --repository-name $ECR_REPO_NAME --force --region $AWS_REGION || true
echo -e "${GREEN}ECR repository deleted.${NC}"

echo -e "${GREEN}=== Cleanup Complete! ===${NC}"
echo -e "${GREEN}All AWS resources for Open Saves have been deleted.${NC}"
echo -e "${GREEN}You can now run deploy-all.sh to deploy a fresh environment.${NC}"
