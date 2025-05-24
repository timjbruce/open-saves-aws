#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Cleanup Script ===${NC}"
echo -e "${RED}WARNING: This will delete all Open Saves resources from AWS${NC}"
echo -e "${RED}This includes the EKS cluster, DynamoDB tables, S3 buckets, and all data${NC}"
echo

# Confirm with the user
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${GREEN}Cleanup cancelled.${NC}"
  exit 0
fi

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
CLUSTER_NAME="open-saves-cluster"
NAMESPACE="open-saves"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"
REDIS_CLUSTER="open-saves-cache"

# Step 1: Delete Kubernetes resources
echo -e "${YELLOW}Step 1: Deleting Kubernetes resources...${NC}"
kubectl delete -f deploy.yaml --ignore-not-found=true
echo -e "${GREEN}Kubernetes resources deleted.${NC}"

# Step 2: Delete EKS nodegroup
echo -e "${YELLOW}Step 2: Deleting EKS nodegroup...${NC}"
if aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION &> /dev/null; then
  aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION
  echo -e "${YELLOW}Waiting for EKS nodegroup to be deleted...${NC}"
  aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION
  echo -e "${GREEN}EKS nodegroup deleted.${NC}"
else
  echo -e "${GREEN}EKS nodegroup does not exist.${NC}"
fi

# Step 3: Delete EKS cluster
echo -e "${YELLOW}Step 3: Deleting EKS cluster...${NC}"
if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
  aws eks delete-cluster --name $CLUSTER_NAME --region $AWS_REGION
  echo -e "${YELLOW}Waiting for EKS cluster to be deleted...${NC}"
  aws eks wait cluster-deleted --name $CLUSTER_NAME --region $AWS_REGION
  echo -e "${GREEN}EKS cluster deleted.${NC}"
else
  echo -e "${GREEN}EKS cluster does not exist.${NC}"
fi

# Step 4: Delete IAM roles
echo -e "${YELLOW}Step 4: Deleting IAM roles...${NC}"
if aws iam get-role --role-name open-saves-eks-cluster-role &> /dev/null; then
  aws iam detach-role-policy --role-name open-saves-eks-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  aws iam delete-role --role-name open-saves-eks-cluster-role
  echo -e "${GREEN}EKS cluster role deleted.${NC}"
else
  echo -e "${GREEN}EKS cluster role does not exist.${NC}"
fi

if aws iam get-role --role-name open-saves-eks-node-role &> /dev/null; then
  aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
  aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
  aws iam detach-role-policy --role-name open-saves-eks-node-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
  aws iam delete-role --role-name open-saves-eks-node-role
  echo -e "${GREEN}EKS node role deleted.${NC}"
else
  echo -e "${GREEN}EKS node role does not exist.${NC}"
fi

# Step 5: Delete CloudFormation stack
echo -e "${YELLOW}Step 5: Deleting CloudFormation stack...${NC}"
if aws cloudformation describe-stacks --stack-name open-saves-resources --region $AWS_REGION &> /dev/null; then
  aws cloudformation delete-stack --stack-name open-saves-resources --region $AWS_REGION
  echo -e "${YELLOW}Waiting for CloudFormation stack to be deleted...${NC}"
  aws cloudformation wait stack-delete-complete --stack-name open-saves-resources --region $AWS_REGION
  echo -e "${GREEN}CloudFormation stack deleted.${NC}"
else
  echo -e "${GREEN}CloudFormation stack does not exist.${NC}"
fi

# Step 6: Delete ECR repository
echo -e "${YELLOW}Step 6: Deleting ECR repository...${NC}"
if aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION &> /dev/null; then
  aws ecr delete-repository --repository-name $ECR_REPO_NAME --force --region $AWS_REGION
  echo -e "${GREEN}ECR repository deleted.${NC}"
else
  echo -e "${GREEN}ECR repository does not exist.${NC}"
fi

# Step 7: Delete VPC resources
echo -e "${YELLOW}Step 7: Finding and deleting VPC resources...${NC}"
echo -e "${YELLOW}Looking for Open Saves VPCs...${NC}"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=open-saves-vpc" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

if [ "$VPC_ID" != "None" ] && [ ! -z "$VPC_ID" ]; then
  echo -e "${YELLOW}Found VPC: $VPC_ID${NC}"
  
  # Delete internet gateway
  echo -e "${YELLOW}Deleting Internet Gateway...${NC}"
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text --region $AWS_REGION)
  if [ "$IGW_ID" != "None" ] && [ ! -z "$IGW_ID" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION
    echo -e "${GREEN}Internet Gateway deleted.${NC}"
  fi
  
  # Delete subnets
  echo -e "${YELLOW}Deleting Subnets...${NC}"
  SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
  for SUBNET_ID in $SUBNET_IDS; do
    aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $AWS_REGION
  done
  echo -e "${GREEN}Subnets deleted.${NC}"
  
  # Delete route tables
  echo -e "${YELLOW}Deleting Route Tables...${NC}"
  RTB_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?RouteTableId!=`'$MAIN_RTB_ID'`].RouteTableId' --output text --region $AWS_REGION)
  for RTB_ID in $RTB_IDS; do
    aws ec2 delete-route-table --route-table-id $RTB_ID --region $AWS_REGION
  done
  echo -e "${GREEN}Route Tables deleted.${NC}"
  
  # Delete security groups
  echo -e "${YELLOW}Deleting Security Groups...${NC}"
  SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $AWS_REGION)
  for SG_ID in $SG_IDS; do
    aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION
  done
  echo -e "${GREEN}Security Groups deleted.${NC}"
  
  # Delete VPC
  echo -e "${YELLOW}Deleting VPC...${NC}"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION
  echo -e "${GREEN}VPC deleted.${NC}"
else
  echo -e "${GREEN}No Open Saves VPC found.${NC}"
fi

# Step 8: Delete ElastiCache cluster
echo -e "${YELLOW}Step 8: Deleting ElastiCache cluster...${NC}"
if aws elasticache describe-cache-clusters --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION &> /dev/null; then
  aws elasticache delete-cache-cluster --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
  echo -e "${YELLOW}Waiting for ElastiCache cluster to be deleted...${NC}"
  aws elasticache wait cache-cluster-deleted --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
  echo -e "${GREEN}ElastiCache cluster deleted.${NC}"
else
  echo -e "${GREEN}ElastiCache cluster does not exist.${NC}"
fi

# Step 9: Delete ElastiCache subnet group
echo -e "${YELLOW}Step 9: Deleting ElastiCache subnet group...${NC}"
if aws elasticache describe-cache-subnet-groups --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION &> /dev/null; then
  aws elasticache delete-cache-subnet-group --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION
  echo -e "${GREEN}ElastiCache subnet group deleted.${NC}"
else
  echo -e "${GREEN}ElastiCache subnet group does not exist.${NC}"
fi

# Step 10: Delete DynamoDB tables
echo -e "${YELLOW}Step 10: Deleting DynamoDB tables...${NC}"
for TABLE in "open-saves-stores" "open-saves-records" "open-saves-metadata"; do
  if aws dynamodb describe-table --table-name $TABLE --region $AWS_REGION &> /dev/null; then
    aws dynamodb delete-table --table-name $TABLE --region $AWS_REGION
    echo -e "${YELLOW}Waiting for $TABLE table to be deleted...${NC}"
    aws dynamodb wait table-not-exists --table-name $TABLE --region $AWS_REGION
    echo -e "${GREEN}$TABLE table deleted.${NC}"
  else
    echo -e "${GREEN}$TABLE table does not exist.${NC}"
  fi
done

# Step 11: Delete S3 bucket
echo -e "${YELLOW}Step 11: Deleting S3 bucket...${NC}"
if aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
  echo -e "${YELLOW}Emptying S3 bucket...${NC}"
  aws s3 rm s3://$S3_BUCKET --recursive
  aws s3api delete-bucket --bucket $S3_BUCKET --region $AWS_REGION
  echo -e "${GREEN}S3 bucket deleted.${NC}"
else
  echo -e "${GREEN}S3 bucket does not exist.${NC}"
fi

echo -e "${GREEN}=== Cleanup Complete! ===${NC}"
echo -e "${GREEN}All Open Saves resources have been deleted from AWS.${NC}"
