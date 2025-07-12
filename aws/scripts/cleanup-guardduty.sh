#!/bin/bash
# Script to check for GuardDuty resources in the Open Saves VPC and clean them up

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== GuardDuty Cleanup for Open Saves VPC ===${NC}"

# Get the VPC ID
vpc_id=$(cd /home/ec2-user/projects/open-saves-aws/aws && terraform state show module.step1_cluster_ecr.aws_vpc.eks_vpc 2>/dev/null | grep "id" | head -1 | awk '{print $3}' | tr -d '"')

if [ -z "$vpc_id" ]; then
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=open-saves-cluster-new-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null)
fi

if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
    echo -e "${RED}Could not find the Open Saves VPC ID.${NC}"
    exit 1
fi

echo -e "${YELLOW}Found Open Saves VPC: $vpc_id${NC}"

# Check if GuardDuty is enabled
detector_id=$(aws guardduty list-detectors --query "DetectorIds[0]" --output text)

if [ "$detector_id" == "None" ] || [ -z "$detector_id" ]; then
    echo -e "${GREEN}GuardDuty is not enabled. No cleanup needed.${NC}"
    exit 0
fi

echo -e "${YELLOW}GuardDuty is enabled with detector ID: $detector_id${NC}"

# Find GuardDuty network interfaces in the VPC
eni_json=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query "NetworkInterfaces[?contains(Description, 'GuardDuty') || contains(Description, 'guardduty') || contains(InterfaceType, 'aws-managed')].{ID:NetworkInterfaceId,Description:Description,SecurityGroups:Groups[0].GroupId}" \
    --output json)

# Extract ENI IDs
eni_ids=$(echo "$eni_json" | jq -r '.[].ID')

if [ -z "$eni_ids" ] || [ "$eni_ids" == "null" ]; then
    echo -e "${GREEN}No GuardDuty network interfaces found in VPC $vpc_id.${NC}"
else
    # Collect security group IDs for later deletion
    sg_ids=$(echo "$eni_json" | jq -r '.[].SecurityGroups' | sort | uniq)
    
    # Delete each ENI
    for eni_id in $eni_ids; do
        echo -e "${YELLOW}Deleting network interface $eni_id...${NC}"
        
        # First, try to detach if it's attached
        attachment_id=$(aws ec2 describe-network-interfaces --network-interface-ids "$eni_id" --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null)
        
        if [ -n "$attachment_id" ] && [ "$attachment_id" != "None" ] && [ "$attachment_id" != "null" ]; then
            aws ec2 detach-network-interface --attachment-id "$attachment_id" --force
            aws ec2 wait network-interface-available --network-interface-ids "$eni_id"
        fi
        
        # Now delete the ENI
        aws ec2 delete-network-interface --network-interface-id "$eni_id"
        echo -e "${GREEN}Deleted network interface $eni_id${NC}"
    done
    
    # Delete GuardDuty security groups
    if [ -n "$sg_ids" ]; then
        for sg_id in $sg_ids; do
            if [ -n "$sg_id" ] && [ "$sg_id" != "null" ]; then
                echo -e "${YELLOW}Deleting security group $sg_id...${NC}"
                
                # Check if this is the default security group
                is_default=$(aws ec2 describe-security-groups --group-ids "$sg_id" --query "SecurityGroups[0].GroupName" --output text 2>/dev/null)
                
                if [ "$is_default" == "default" ]; then
                    echo -e "${YELLOW}Skipping default security group${NC}"
                    continue
                fi
                
                # Try to delete the security group
                if aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null; then
                    echo -e "${GREEN}Deleted security group $sg_id${NC}"
                else
                    echo -e "${RED}Failed to delete security group $sg_id${NC}"
                fi
            fi
        done
    fi
fi

echo -e "${GREEN}GuardDuty cleanup completed successfully.${NC}"
