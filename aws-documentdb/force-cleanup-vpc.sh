#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

VPC_ID="vpc-0480770936ff81fe0"
REGION="us-west-2"

echo -e "${YELLOW}=== Force VPC Cleanup Script ===${NC}"
echo -e "${YELLOW}This script will forcefully delete the VPC and all associated resources${NC}"
echo -e "${RED}WARNING: This will delete all resources in the VPC!${NC}"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup aborted.${NC}"
    exit 1
fi

# Step 1: Force delete any remaining CloudFormation stacks
echo -e "${YELLOW}Step 1: Force deleting CloudFormation stacks...${NC}"
STACKS=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_FAILED --query 'StackSummaries[?contains(StackName, `open-saves`) || contains(StackName, `eks`)].StackName' --output text)
for STACK in $STACKS; do
    echo "Force deleting stack $STACK"
    aws cloudformation delete-stack --region $REGION --stack-name $STACK || echo "Failed to delete $STACK, continuing..."
done
echo -e "${GREEN}CloudFormation stacks deletion initiated.${NC}"

# Step 2: Delete any remaining network interfaces
echo -e "${YELLOW}Step 2: Deleting network interfaces...${NC}"
ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text)
for ENI_ID in $ENI_IDS; do
    echo "Detaching network interface $ENI_ID if attached"
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text)
    if [ "$ATTACHMENT_ID" != "None" ] && [ -n "$ATTACHMENT_ID" ]; then
        aws ec2 detach-network-interface --region $REGION --attachment-id $ATTACHMENT_ID --force || echo "Failed to detach $ENI_ID, continuing..."
        echo "Waiting for detachment to complete..."
        sleep 10
    fi
    
    echo "Deleting network interface $ENI_ID"
    aws ec2 delete-network-interface --region $REGION --network-interface-id $ENI_ID || echo "Failed to delete $ENI_ID, continuing..."
done
echo -e "${GREEN}Network interfaces deleted.${NC}"

# Step 3: Delete all security groups (except default)
echo -e "${YELLOW}Step 3: Deleting security groups...${NC}"
SG_IDS=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
for SG_ID in $SG_IDS; do
    echo "Deleting security group $SG_ID"
    aws ec2 delete-security-group --region $REGION --group-id $SG_ID || echo "Failed to delete $SG_ID, continuing..."
done
echo -e "${GREEN}Security groups deletion attempted.${NC}"

# Step 4: Detach and delete internet gateway
echo -e "${YELLOW}Step 4: Detaching and deleting internet gateway...${NC}"
IGW_ID=$(aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text)
if [ -n "$IGW_ID" ]; then
    echo "Detaching internet gateway $IGW_ID"
    aws ec2 detach-internet-gateway --region $REGION --internet-gateway-id $IGW_ID --vpc-id $VPC_ID || echo "Failed to detach $IGW_ID, continuing..."
    echo "Deleting internet gateway $IGW_ID"
    aws ec2 delete-internet-gateway --region $REGION --internet-gateway-id $IGW_ID || echo "Failed to delete $IGW_ID, continuing..."
    echo -e "${GREEN}Internet gateway deletion attempted.${NC}"
else
    echo -e "${YELLOW}No internet gateway found.${NC}"
fi

# Step 5: Delete subnets
echo -e "${YELLOW}Step 5: Deleting subnets...${NC}"
SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
for SUBNET_ID in $SUBNET_IDS; do
    echo "Deleting subnet $SUBNET_ID"
    aws ec2 delete-subnet --region $REGION --subnet-id $SUBNET_ID || echo "Failed to delete $SUBNET_ID, continuing..."
done
echo -e "${GREEN}Subnet deletion attempted.${NC}"

# Step 6: Delete route tables (except main)
echo -e "${YELLOW}Step 6: Deleting route tables...${NC}"
RT_IDS=$(aws ec2 describe-route-tables --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
for RT_ID in $RT_IDS; do
    # First, disassociate any subnet associations
    ASSOC_IDS=$(aws ec2 describe-route-tables --region $REGION --route-table-ids $RT_ID --query 'RouteTables[].Associations[?Main!=`true`].RouteTableAssociationId' --output text)
    for ASSOC_ID in $ASSOC_IDS; do
        echo "Disassociating route table association $ASSOC_ID"
        aws ec2 disassociate-route-table --region $REGION --association-id $ASSOC_ID || echo "Failed to disassociate $ASSOC_ID, continuing..."
    done
    
    echo "Deleting route table $RT_ID"
    aws ec2 delete-route-table --region $REGION --route-table-id $RT_ID || echo "Failed to delete $RT_ID, continuing..."
done
echo -e "${GREEN}Route table deletion attempted.${NC}"

# Step 7: Delete VPC
echo -e "${YELLOW}Step 7: Deleting VPC...${NC}"
aws ec2 delete-vpc --region $REGION --vpc-id $VPC_ID || echo "Failed to delete VPC $VPC_ID"

# Step 8: Check if VPC was deleted
echo -e "${YELLOW}Step 8: Checking if VPC was deleted...${NC}"
if aws ec2 describe-vpcs --region $REGION --vpc-ids $VPC_ID 2>&1 | grep -q "does not exist"; then
    echo -e "${GREEN}VPC $VPC_ID was successfully deleted.${NC}"
else
    echo -e "${RED}VPC $VPC_ID still exists. Manual cleanup may be required.${NC}"
fi

echo -e "${GREEN}=== Force VPC Cleanup Complete ===${NC}"
