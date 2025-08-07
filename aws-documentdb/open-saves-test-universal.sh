#!/bin/bash

# open-saves-test-universal.sh - Region-independent comprehensive test script for Open Saves AWS implementation

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_ENDPOINT=""
DEFAULT_ARCH="arm64"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    --architecture)
      ARCH="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--region REGION] [--endpoint ENDPOINT] [--architecture ARCH]"
      echo "  --region: AWS region (default: us-east-1)"
      echo "  --endpoint: Open Saves endpoint URL (auto-detected if not provided)"
      echo "  --architecture: arm64 or amd64 (default: arm64)"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Set defaults
REGION=${REGION:-$DEFAULT_REGION}
ARCH=${ARCH:-$DEFAULT_ARCH}

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Open Saves Universal Test Script${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${YELLOW}Region: ${REGION}${NC}"
echo -e "${YELLOW}Architecture: ${ARCH}${NC}"

# Auto-detect endpoint if not provided
if [ -z "$ENDPOINT" ]; then
  echo -e "${YELLOW}Auto-detecting Open Saves endpoint...${NC}"
  
  # Try to get load balancer from kubectl
  LB_HOSTNAME=$(kubectl get svc -n open-saves open-saves -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  
  if [ -n "$LB_HOSTNAME" ]; then
    ENDPOINT="http://${LB_HOSTNAME}:8080"
    echo -e "${GREEN}Found endpoint via kubectl: ${ENDPOINT}${NC}"
  else
    # Try to get from SSM Parameter Store
    LB_HOSTNAME=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step4/load_balancer_hostname_${ARCH}" --query 'Parameter.Value' --output text 2>/dev/null)
    
    if [ -n "$LB_HOSTNAME" ] && [ "$LB_HOSTNAME" != "None" ]; then
      ENDPOINT="http://${LB_HOSTNAME}:8080"
      echo -e "${GREEN}Found endpoint via SSM: ${ENDPOINT}${NC}"
    else
      echo -e "${RED}Error: Could not auto-detect endpoint. Please provide --endpoint parameter${NC}"
      exit 1
    fi
  fi
fi

echo -e "${YELLOW}Using endpoint: ${ENDPOINT}${NC}"

# Function to get DocumentDB connection details
get_documentdb_details() {
  echo -e "${YELLOW}Getting DocumentDB connection details...${NC}"
  
  DOCDB_ENDPOINT=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step2/documentdb_endpoint" --query 'Parameter.Value' --output text 2>/dev/null)
  DOCDB_PORT=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step2/documentdb_port" --query 'Parameter.Value' --output text 2>/dev/null)
  DOCDB_USERNAME=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step2/documentdb_username" --query 'Parameter.Value' --output text 2>/dev/null)
  DOCDB_PASSWORD_SECRET_ARN=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step2/documentdb_password_secret_arn" --query 'Parameter.Value' --output text 2>/dev/null)
  
  if [ -n "$DOCDB_PASSWORD_SECRET_ARN" ]; then
    DOCDB_PASSWORD=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$DOCDB_PASSWORD_SECRET_ARN" --query 'SecretString' --output text 2>/dev/null)
  fi
  
  echo -e "${GREEN}DocumentDB Endpoint: ${DOCDB_ENDPOINT}:${DOCDB_PORT}${NC}"
  echo -e "${GREEN}DocumentDB Username: ${DOCDB_USERNAME}${NC}"
}

# Function to create test instance
create_test_instance() {
  local arch=$1
  local instance_type
  local ami_id
  
  echo -e "${YELLOW}Creating test instance for ${arch} architecture...${NC}"
  
  # Determine instance type and AMI based on architecture
  if [ "$arch" == "amd64" ]; then
    instance_type="t3.micro"
    ami_filter="x86_64"
  else
    instance_type="t4g.micro"
    ami_filter="arm64"
  fi
  
  # Get latest Amazon Linux 2 AMI for the architecture
  ami_id=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --filters \
      "Name=name,Values=amzn2-ami-hvm-*" \
      "Name=architecture,Values=${ami_filter}" \
      "Name=virtualization-type,Values=hvm" \
      "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null)
  
  if [ -z "$ami_id" ] || [ "$ami_id" == "None" ]; then
    echo -e "${RED}Error: Could not find a valid AMI ID for $arch architecture in ${REGION}${NC}"
    return 1
  fi
  
  echo -e "${GREEN}Using AMI: ${ami_id} (${instance_type})${NC}"
  
  # Get VPC and subnet information
  VPC_ID=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step1/vpc_id" --query 'Parameter.Value' --output text 2>/dev/null)
  PRIVATE_SUBNETS=$(aws ssm get-parameter --region "$REGION" --name "/open-saves/step1/private_subnet_ids" --query 'Parameter.Value' --output text 2>/dev/null)
  
  if [ -z "$VPC_ID" ] || [ -z "$PRIVATE_SUBNETS" ]; then
    echo -e "${RED}Error: Could not get VPC/subnet information from SSM${NC}"
    return 1
  fi
  
  # Use first private subnet
  SUBNET_ID=$(echo "$PRIVATE_SUBNETS" | cut -d',' -f1)
  
  # Create security group for test instance
  SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "open-saves-test-sg-$(date +%s)" \
    --description "Security group for Open Saves test instance" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text 2>/dev/null)
  
  if [ -z "$SG_ID" ]; then
    echo -e "${RED}Error: Could not create security group${NC}"
    return 1
  fi
  
  # Allow outbound HTTPS and DocumentDB access
  aws ec2 authorize-security-group-egress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 >/dev/null 2>&1
    
  aws ec2 authorize-security-group-egress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 >/dev/null 2>&1
    
  aws ec2 authorize-security-group-egress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 27017 \
    --cidr 10.0.0.0/8 >/dev/null 2>&1
  
  # Create user data script
  USER_DATA=$(cat << 'EOF'
#!/bin/bash
yum update -y
yum install -y curl jq

# Install MongoDB client
cat > /etc/yum.repos.d/mongodb-org-4.4.repo << 'REPO_EOF'
[mongodb-org-4.4]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.4/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.4.asc
REPO_EOF

yum install -y mongodb-org-shell

# Create test script
cat > /home/ec2-user/test-open-saves.sh << 'TEST_EOF'
#!/bin/bash

ENDPOINT="$1"
DOCDB_ENDPOINT="$2"
DOCDB_PORT="$3"
DOCDB_USERNAME="$4"
DOCDB_PASSWORD="$5"

echo "Testing Open Saves API at: $ENDPOINT"

# Test 1: Health check
echo "=== Test 1: Health Check ==="
curl -f "$ENDPOINT/health" && echo " ✓ Health check passed" || echo " ✗ Health check failed"

# Test 2: Create a store
echo "=== Test 2: Create Store ==="
STORE_ID="test-store-$(date +%s)"
CREATE_RESPONSE=$(curl -s -X POST "$ENDPOINT/v1/stores" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$STORE_ID\", \"tags\": {\"test\": \"true\"}}")

echo "Create store response: $CREATE_RESPONSE"

# Test 3: List stores
echo "=== Test 3: List Stores ==="
LIST_RESPONSE=$(curl -s "$ENDPOINT/v1/stores")
echo "List stores response: $LIST_RESPONSE"

# Test 4: Create a record
echo "=== Test 4: Create Record ==="
RECORD_KEY="test-record-$(date +%s)"
RECORD_RESPONSE=$(curl -s -X POST "$ENDPOINT/v1/stores/$STORE_ID/records" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"$RECORD_KEY\", \"blob_size\": 13, \"properties\": {\"test\": \"data\"}}")

echo "Create record response: $RECORD_RESPONSE"

# Test 5: Verify data in DocumentDB
echo "=== Test 5: Verify Data in DocumentDB ==="
if [ -n "$DOCDB_ENDPOINT" ] && [ -n "$DOCDB_PASSWORD" ]; then
  echo "Connecting to DocumentDB to verify data..."
  
  # Download RDS CA certificate
  wget -q https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem -O /tmp/rds-ca-2019-root.pem
  
  # Query DocumentDB for the created store
  mongo --ssl --host "$DOCDB_ENDPOINT:$DOCDB_PORT" \
    --sslCAFile /tmp/rds-ca-2019-root.pem \
    --username "$DOCDB_USERNAME" \
    --password "$DOCDB_PASSWORD" \
    --eval "
      db = db.getSiblingDB('open-saves');
      print('=== Stores Collection ===');
      db.stores.find({store_id: '$STORE_ID'}).forEach(printjson);
      print('=== Records Collection ===');
      db.records.find({store_id: '$STORE_ID'}).forEach(printjson);
      print('=== Metadata Collection ===');
      db.metadata.find({store_id: '$STORE_ID'}).forEach(printjson);
    " 2>/dev/null && echo " ✓ DocumentDB verification passed" || echo " ✗ DocumentDB verification failed"
else
  echo "DocumentDB credentials not provided, skipping database verification"
fi

echo "=== Test Complete ==="
TEST_EOF

chmod +x /home/ec2-user/test-open-saves.sh
EOF
)
  
  # Launch instance
  INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$ami_id" \
    --count 1 \
    --instance-type "$instance_type" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --user-data "$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=open-saves-test-$(date +%s)},{Key=Project,Value=open-saves}]" \
    --query 'Instances[0].InstanceId' \
    --output text 2>/dev/null)
  
  if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not launch test instance${NC}"
    return 1
  fi
  
  echo -e "${GREEN}Test instance launched: ${INSTANCE_ID}${NC}"
  echo -e "${YELLOW}Waiting for instance to be ready...${NC}"
  
  # Wait for instance to be running
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
  
  # Wait a bit more for user data to complete
  echo -e "${YELLOW}Waiting for user data script to complete...${NC}"
  sleep 60
  
  echo "$INSTANCE_ID:$SG_ID"
}

# Function to run tests on the instance
run_tests_on_instance() {
  local instance_id=$1
  
  echo -e "${YELLOW}Running tests on instance ${instance_id}...${NC}"
  
  # Run the test script via SSM
  COMMAND_ID=$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$instance_id" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=['/home/ec2-user/test-open-saves.sh \"$ENDPOINT\" \"$DOCDB_ENDPOINT\" \"$DOCDB_PORT\" \"$DOCDB_USERNAME\" \"$DOCDB_PASSWORD\"']" \
    --query 'Command.CommandId' \
    --output text 2>/dev/null)
  
  if [ -z "$COMMAND_ID" ]; then
    echo -e "${RED}Error: Could not send command to instance${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Command sent, waiting for completion...${NC}"
  
  # Wait for command to complete
  aws ssm wait command-executed \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$instance_id"
  
  # Get command output
  OUTPUT=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$instance_id" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null)
  
  ERROR_OUTPUT=$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$instance_id" \
    --query 'StandardErrorContent' \
    --output text 2>/dev/null)
  
  echo -e "${BLUE}=== Test Results ===${NC}"
  echo "$OUTPUT"
  
  if [ -n "$ERROR_OUTPUT" ] && [ "$ERROR_OUTPUT" != "None" ]; then
    echo -e "${RED}=== Errors ===${NC}"
    echo "$ERROR_OUTPUT"
  fi
}

# Function to cleanup resources
cleanup_resources() {
  local instance_id=$1
  local sg_id=$2
  
  echo -e "${YELLOW}Cleaning up resources...${NC}"
  
  if [ -n "$instance_id" ]; then
    echo -e "${YELLOW}Terminating instance ${instance_id}...${NC}"
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$instance_id" >/dev/null 2>&1
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$instance_id" 2>/dev/null
  fi
  
  if [ -n "$sg_id" ]; then
    echo -e "${YELLOW}Deleting security group ${sg_id}...${NC}"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" >/dev/null 2>&1
  fi
  
  echo -e "${GREEN}Cleanup complete${NC}"
}

# Main execution
main() {
  # Get DocumentDB details
  get_documentdb_details
  
  # Create test instance
  echo -e "${YELLOW}Creating test instance...${NC}"
  INSTANCE_INFO=$(create_test_instance "$ARCH")
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create test instance${NC}"
    exit 1
  fi
  
  INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d':' -f1)
  SG_ID=$(echo "$INSTANCE_INFO" | cut -d':' -f2)
  
  # Set up cleanup trap
  trap "cleanup_resources $INSTANCE_ID $SG_ID" EXIT
  
  # Run tests
  run_tests_on_instance "$INSTANCE_ID"
  
  echo -e "${GREEN}Test execution complete!${NC}"
}

# Run main function
main
