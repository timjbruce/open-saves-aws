#!/bin/bash

# cleanup.sh - Script to clean up Open Saves AWS resources
# This script is a wrapper around the deploy-targeted.sh script with the --destroy flag

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Cleanup ===${NC}"
echo -e "${YELLOW}This script will destroy all Open Saves AWS resources${NC}"
echo -e "${RED}WARNING: This action is irreversible!${NC}"
echo -e "${YELLOW}===============================${NC}"

# Ask for confirmation
read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${GREEN}Cleanup cancelled.${NC}"
  exit 0
fi

# Ask for architecture
echo -e "${YELLOW}Which architecture do you want to clean up?${NC}"
echo "1. AMD64 (x86_64)"
echo "2. ARM64 (aarch64)"
echo "3. Both"
read -p "Enter your choice (1-3): " arch_choice

case $arch_choice in
  1) ARCHITECTURE="amd64" ;;
  2) ARCHITECTURE="arm64" ;;
  3) ARCHITECTURE="both" ;;
  *) 
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

# Execute the deploy-targeted.sh script with the --destroy flag
echo -e "${YELLOW}Destroying Open Saves AWS resources for $ARCHITECTURE architecture...${NC}"
$(dirname "$0")/deploy-targeted.sh --step all --arch $ARCHITECTURE --destroy

echo -e "${GREEN}Cleanup completed successfully!${NC}"
