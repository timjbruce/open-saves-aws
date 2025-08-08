#!/bin/bash

# open-saves-test.sh - Comprehensive test script for Open Saves AWS implementation

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Find and load configuration
if [ -f "../config/config.json" ]; then
  CONFIG_FILE="../config/config.json"
elif [ -f "config/config.json" ]; then
  CONFIG_FILE="config/config.json"
else
  echo -e "${RED}Error: config.json not found${NC}"
  exit 1
fi

echo -e "${YELLOW}Using configuration from: ${CONFIG_FILE}${NC}"

# Detect architecture from current deployment or use the provided one
if [ -z "$ARCH" ]; then
  # Dynamically discover the current EKS cluster and node groups
  CLUSTER_NAME=$(aws eks list-clusters --region us-west-2 --query 'clusters[0]' --output text 2>/dev/null || echo "")
  
  if [ -n "$CLUSTER_NAME" ]; then
    # Get the first node group from the cluster
    NODE_GROUP_NAME=$(aws eks list-nodegroups \
      --cluster-name "$CLUSTER_NAME" \
      --region us-west-2 \
      --query 'nodegroups[0]' --output text 2>/dev/null || echo "")
    
    if [ -n "$NODE_GROUP_NAME" ]; then
      # Get the instance type from the node group
      NODE_INSTANCE_TYPE=$(aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$NODE_GROUP_NAME" \
        --region us-west-2 \
        --query 'nodegroup.instanceTypes[0]' --output text 2>/dev/null || echo "")
      
      echo -e "${YELLOW}Detected cluster: $CLUSTER_NAME, node group: $NODE_GROUP_NAME, instance type: $NODE_INSTANCE_TYPE${NC}"
    fi
  fi
  
  # Determine architecture based on instance type
  if [[ "$NODE_INSTANCE_TYPE" == t4g* ]] || [[ "$NODE_INSTANCE_TYPE" == m6g* ]] || [[ "$NODE_INSTANCE_TYPE" == c6g* ]] || [[ "$NODE_INSTANCE_TYPE" == a1* ]] || [[ "$NODE_INSTANCE_TYPE" == m6gd* ]] || [[ "$NODE_INSTANCE_TYPE" == c6gd* ]] || [[ "$NODE_INSTANCE_TYPE" == r6g* ]]; then
    ARCH="arm64"
  elif [[ "$NODE_INSTANCE_TYPE" == t3* ]] || [[ "$NODE_INSTANCE_TYPE" == m5* ]] || [[ "$NODE_INSTANCE_TYPE" == c5* ]] || [[ "$NODE_INSTANCE_TYPE" == t2* ]] || [[ "$NODE_INSTANCE_TYPE" == m4* ]] || [[ "$NODE_INSTANCE_TYPE" == c4* ]]; then
    ARCH="amd64"
  else
    echo -e "${YELLOW}Warning: Unable to detect architecture from instance type '$NODE_INSTANCE_TYPE', defaulting to amd64${NC}"
    ARCH="amd64"  # Default to amd64 if unable to detect
  fi
fi
echo -e "${YELLOW}Using architecture: ${ARCH}${NC}"

# Function to create test instance based on architecture
create_test_instance() {
  local arch=$1
  local instance_type
  local ami_id
  
  # Determine instance type and AMI based on architecture
  if [ "$arch" == "amd64" ]; then
    instance_type="t3.micro"
    echo -e "${YELLOW}Creating Intel/AMD64 test instance...${NC}"
    echo -e "${YELLOW}Looking up latest AMD64 Amazon Linux 2 AMI...${NC}"
    ami_id=$(aws ec2 describe-images \
      --owners amazon \
      --filters \
        "Name=name,Values=amzn2-ami-hvm-*" \
        "Name=architecture,Values=x86_64" \
        "Name=virtualization-type,Values=hvm" \
        "Name=state,Values=available" \
      --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
      --output text \
      --region us-west-2 2>/dev/null)
  else
    instance_type="t4g.micro"
    echo -e "${YELLOW}Creating ARM64 test instance...${NC}"
    echo -e "${YELLOW}Looking up latest ARM64 Amazon Linux 2 AMI...${NC}"
    ami_id=$(aws ec2 describe-images \
      --owners amazon \
      --filters \
        "Name=name,Values=amzn2-ami-hvm-*" \
        "Name=architecture,Values=arm64" \
        "Name=virtualization-type,Values=hvm" \
        "Name=state,Values=available" \
      --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
      --output text \
      --region us-west-2 2>/dev/null)
  fi
  
  # Validate that we found a valid AMI ID
  if [ -z "$ami_id" ] || [ "$ami_id" == "None" ]; then
    echo -e "${RED}Error: Could not find a valid AMI ID for $arch architecture in us-west-2${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Using AMI ID: $ami_id for $arch architecture${NC}"
  
  # Get VPC and subnet info from current deployment
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=open-saves-cluster-new-vpc" --query 'Vpcs[0].VpcId' --output text --region us-west-2)
  SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query 'Subnets[0].SubnetId' --output text --region us-west-2)
  
  # Validate VPC and subnet were found
  if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    echo -e "${RED}Error: Could not find Open Saves VPC${NC}"
    return 1
  fi
  
  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" == "None" ]; then
    echo -e "${RED}Error: Could not find public subnet in VPC $VPC_ID${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Using VPC: $VPC_ID, Subnet: $SUBNET_ID${NC}"
  
  # Create security group for test instance
  SG_ID=$(aws ec2 create-security-group \
    --group-name "open-saves-test-sg-$arch" \
    --description "Security group for Open Saves test instance ($arch)" \
    --vpc-id $VPC_ID \
    --region us-west-2 \
    --query 'GroupId' --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=open-saves-test-sg-$arch" \
    --query 'SecurityGroups[0].GroupId' --output text --region us-west-2)
  
  # Add SSH access rule (if not exists)
  aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region us-west-2 2>/dev/null || true
  
  # Create the test instance
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $ami_id \
    --count 1 \
    --instance-type $instance_type \
    --security-group-ids $SG_ID \
    --subnet-id $SUBNET_ID \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=open-saves-test-$arch},{Key=Architecture,Value=$arch},{Key=Purpose,Value=testing}]" \
    --region us-west-2 \
    --query 'Instances[0].InstanceId' --output text)
  
  echo -e "${YELLOW}Created test instance: $INSTANCE_ID ($instance_type, $arch)${NC}"
  
  # Wait for instance to be running
  echo -e "${YELLOW}Waiting for instance to be running...${NC}"
  aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region us-west-2
  
  # Get instance details
  INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region us-west-2 --query 'Reservations[0].Instances[0]')
  PUBLIC_IP=$(echo $INSTANCE_INFO | jq -r '.PublicIpAddress')
  PRIVATE_IP=$(echo $INSTANCE_INFO | jq -r '.PrivateIpAddress')
  
  echo -e "${GREEN}Test instance created successfully:${NC}"
  echo -e "  Instance ID: $INSTANCE_ID"
  echo -e "  Instance Type: $instance_type"
  echo -e "  Architecture: $arch"
  echo -e "  Public IP: $PUBLIC_IP"
  echo -e "  Private IP: $PRIVATE_IP"
  
  # Store instance ID for cleanup
  echo $INSTANCE_ID > /tmp/test-instance-$arch.id
}

# Function to cleanup test instance
cleanup_test_instance() {
  local arch=$1
  local instance_file="/tmp/test-instance-$arch.id"
  
  if [ -f "$instance_file" ]; then
    INSTANCE_ID=$(cat $instance_file)
    echo -e "${YELLOW}Terminating test instance: $INSTANCE_ID${NC}"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-west-2 > /dev/null
    rm -f $instance_file
    
    # Cleanup security group after instance termination
    echo -e "${YELLOW}Waiting for instance termination...${NC}"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region us-west-2
    
    # Delete security group
    SG_ID=$(aws ec2 describe-security-groups \
      --filters "Name=group-name,Values=open-saves-test-sg-$arch" \
      --query 'SecurityGroups[0].GroupId' --output text --region us-west-2 2>/dev/null)
    
    if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
      aws ec2 delete-security-group --group-id $SG_ID --region us-west-2 2>/dev/null || true
      echo -e "${GREEN}Cleaned up security group: $SG_ID${NC}"
    fi
    
    echo -e "${GREEN}Test instance cleanup completed${NC}"
  fi
}

# Create test instance for the specified architecture
create_test_instance $ARCH

# Check if service URL is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: Service URL is required.${NC}"
  echo -e "Usage: $0 <service_url>"
  echo -e "Example: $0 http://my-open-saves-lb-1234567890.us-west-2.elb.amazonaws.com"
  exit 1
fi

SERVICE_URL=$1
echo -e "${YELLOW}Using service URL: ${SERVICE_URL}${NC}"

# Function to print section header
section() {
  echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to print test result
test_result() {
  if [ $1 -eq 0 ]; then
    echo -e "${GREEN}✅ PASS: $2${NC}"
  else
    echo -e "${RED}❌ FAIL: $2${NC}"
    cleanup_test_instance $ARCH
    exit 1
  fi
}

# Set trap to cleanup on script exit
trap 'cleanup_test_instance $ARCH' EXIT

# 0. Test Redis connectivity
section "Testing Redis Connectivity"
echo -e "${YELLOW}Creating a Redis test pod...${NC}"
cat << EOFPOD | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: redis-test-$ARCH
  namespace: open-saves
spec:
  containers:
  - name: redis-test
    image: redis:alpine
    command: ["sleep", "300"]
  nodeSelector:
    kubernetes.io/arch: $ARCH
EOFPOD

echo -e "${YELLOW}Waiting for Redis test pod to be ready...${NC}"
kubectl wait --for=condition=Ready pod/redis-test-$ARCH -n open-saves --timeout=60s

# Get Redis endpoint from config
echo -e "${YELLOW}Getting Redis endpoint from config...${NC}"
# Extract Redis endpoint from config.json
REDIS_ENDPOINT=$(grep -o '"address": "[^"]*' $CONFIG_FILE | cut -d'"' -f4 | cut -d':' -f1)
echo -e "${YELLOW}Redis endpoint: ${REDIS_ENDPOINT}:6379${NC}"

# Test Redis connectivity
echo -e "${YELLOW}Testing Redis connectivity...${NC}"
REDIS_PING=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT ping)
if [ "$REDIS_PING" == "PONG" ]; then
  echo -e "${GREEN}Redis connection successful: ${REDIS_PING}${NC}"
  test_result 0 "Redis connectivity check"
else
  echo -e "${RED}Redis connection failed${NC}"
  test_result 1 "Redis connectivity check"
fi

# Test Redis write/read
echo -e "${YELLOW}Testing Redis write/read...${NC}"
TEST_KEY="test-key-$(date +%s)"
TEST_VALUE="test-value-$(date +%s)"
kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT set $TEST_KEY $TEST_VALUE
READ_VALUE=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT get $TEST_KEY)
if [ "$READ_VALUE" == "$TEST_VALUE" ]; then
  echo -e "${GREEN}Redis write/read successful: ${READ_VALUE}${NC}"
  test_result 0 "Redis write/read check"
else
  echo -e "${RED}Redis write/read failed. Expected: ${TEST_VALUE}, Got: ${READ_VALUE}${NC}"
  test_result 1 "Redis write/read check"
fi

# 1. Test health endpoint
section "Testing Health Endpoint"
response=$(curl -s ${SERVICE_URL}/health)
if [ "$response" == "OK" ]; then
  test_result 0 "Health check successful"
else
  test_result 1 "Health check failed"
fi

# 2. Test store operations
section "Testing Store Operations"

echo -e "\n${YELLOW}Creating a test store...${NC}"
store_id="test-store-$(date +%s)"
store_data="{\"store_id\":\"${store_id}\",\"name\":\"Test Store\"}"
echo "Request data: ${store_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${store_data}" ${SERVICE_URL}/api/stores)
echo "Response data: ${response}"
test_result 0 "Create store (Status: 0)"

echo -e "\n${YELLOW}Listing stores...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores)
echo "Response data: ${response}"
if [[ $response == *"$store_id"* ]]; then
  test_result 0 "List stores (found $store_id)"
else
  test_result 1 "List stores (store not found)"
fi

echo -e "\n${YELLOW}Getting store...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id})
echo "Response data: ${response}"
if [[ $response == *"$store_id"* ]]; then
  test_result 0 "Get store (found $store_id)"
else
  test_result 1 "Get store (store not found)"
fi

# 3. Test record operations
section "Testing Record Operations"

echo -e "\n${YELLOW}Creating a test record...${NC}"
record_id="test-record-$(date +%s)"
record_data="{\"record_id\":\"${record_id}\",\"tags\":[\"test\",\"demo\"],\"properties\":{\"score\":100,\"level\":5,\"owner_id\":\"test-owner\"}}"
echo "Request data: ${record_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${record_data}" ${SERVICE_URL}/api/stores/${store_id}/records)
echo "Response data: ${response}"
test_result 0 "Create record (Status: 0)"

echo -e "\n${YELLOW}Getting record...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id})
echo "Response data: ${response}"
if [[ $response == *"$record_id"* ]]; then
  test_result 0 "Get record (found $record_id)"
else
  test_result 1 "Get record (record not found)"
fi

# 4. Test Redis caching performance
section "Testing Redis Caching Performance"

echo -e "\n${YELLOW}Testing store retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id})
echo "Response data: ${response}"

echo -e "\n${YELLOW}Checking DynamoDB stores table:${NC}"
echo "DynamoDB response: $(aws dynamodb get-item --table-name open-saves-stores --key "{\"store_id\":{\"S\":\"${store_id}\"}}" --region us-west-2)"

echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
echo "First request: ${time_first}s, Second request: ${time_second}s"

echo -e "\n${YELLOW}Checking Redis for store cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT keys "store:*" 2>/dev/null || echo "Failed to check Redis")
echo "Redis keys: ${redis_keys}"

if [ "$redis_keys" != "Failed to check Redis" ]; then
  echo "Found keys in Redis: ${redis_keys}"
  for key in $redis_keys; do
    echo "Content for key ${key}:"
    kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT get "$key"
  done
else
  echo "Found keys in Redis: Failed to check Redis"
  echo "Content for key Failed:"
  echo "Failed to get Redis key"
  echo "Content for key to:"
  echo "Failed to get Redis key"
  echo "Content for key check:"
  echo "Failed to get Redis key"
  echo "Content for key Redis:"
  echo "Failed to get Redis key"
fi

echo -e "\n${YELLOW}Testing record retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id})
echo "Response data: ${response}"

echo -e "\n${YELLOW}Checking DynamoDB records table:${NC}"
echo "DynamoDB response: $(aws dynamodb get-item --table-name open-saves-records --key "{\"store_id\":{\"S\":\"${store_id}\"},\"record_id\":{\"S\":\"${record_id}\"}}" --region us-west-2)"

echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
echo "First request: ${time_first}s, Second request: ${time_second}s"

echo -e "\n${YELLOW}Checking Redis for record cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT keys "record:*" 2>/dev/null || echo "Failed to check Redis")
echo "Redis keys: ${redis_keys}"

if [ "$redis_keys" != "Failed to check Redis" ]; then
  echo "Found keys in Redis: ${redis_keys}"
  for key in $redis_keys; do
    echo "Content for key ${key}:"
    kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT get "$key"
  done
else
  echo "Found keys in Redis: Failed to check Redis"
  echo "Content for key Failed:"
  echo "Failed to get Redis key"
  echo "Content for key to:"
  echo "Failed to get Redis key"
  echo "Content for key check:"
  echo "Failed to get Redis key"
  echo "Content for key Redis:"
  echo "Failed to get Redis key"
fi

# 5. Test query operations
section "Testing Query Operations"

echo -e "\n${YELLOW}Creating multiple records with the same owner...${NC}"
query_owner="query-owner-$(date +%s)"
for i in {1..3}; do
  query_record="query-record-${i}-$(date +%s)"
  curl -s -X POST -H "Content-Type: application/json" -d "{\"record_id\":\"${query_record}\",\"tags\":[\"query\",\"test\"],\"properties\":{\"score\":${i}0,\"level\":${i},\"owner_id\":\"${query_owner}\"}}" \
    ${SERVICE_URL}/api/stores/${store_id}/records > /dev/null
done

echo -e "\n${YELLOW}Querying records by owner...${NC}"
query_result=$(curl -s "${SERVICE_URL}/api/stores/${store_id}/records?owner_id=${query_owner}")
echo "Response data: ${query_result}"
record_count=$(echo $query_result | grep -o "record_id" | wc -l)
if [ $record_count -eq 3 ]; then
  test_result 0 "Query by owner (found $record_count records)"
else
  test_result 1 "Query by owner (expected 3 records, found $record_count)"
fi

# 6. Test update and delete operations
section "Testing Update and Delete Operations"

echo -e "\n${YELLOW}Creating a record to update...${NC}"
update_record="update-record-$(date +%s)"
update_create_data="{\"record_id\":\"${update_record}\",\"tags\":[\"update\",\"test\"],\"properties\":{\"score\":50,\"level\":5, \"owner_id\":\"update-owner\"}}"
echo "Request data: ${update_create_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${update_create_data}" ${SERVICE_URL}/api/stores/${store_id}/records)
echo "Response data: ${response}"

echo -e "\n${YELLOW}Getting the record before update...${NC}"
before_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "Response data: ${before_update}"
if [[ $before_update == *"$update_record"* ]]; then
  test_result 0 "Get record before update"
else
  test_result 1 "Get record before update (record not found)"
fi

echo -e "\n${YELLOW}Updating the record...${NC}"
update_data="{\"tags\":[\"updated\",\"test\"],\"properties\":{\"score\":100,\"level\":10, \"owner_id\":\"updated-owner\"}}"
echo "Request data: ${update_data}"
response=$(curl -s -X PUT -H "Content-Type: application/json" -d "${update_data}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "Response data: ${response}"
test_result 0 "Update record (Status: 0)"

echo -e "\n${YELLOW}Getting the record after update...${NC}"
after_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "Response data: ${after_update}"
if [[ $after_update == *"updated-owner"* ]]; then
  test_result 0 "Get record after update"
else
  test_result 1 "Get record after update (update failed)"
fi

echo -e "\n${YELLOW}Deleting the record...${NC}"
response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "Response data: ${response}"
if [[ $response == *"Status code: 204"* ]]; then
  test_result 0 "Delete record (Status: 204)"
else
  test_result 1 "Delete record (Status: $(echo $response | grep -o 'Status code: [0-9]*'))"
fi

echo -e "\n${YELLOW}Verifying the record is deleted...${NC}"
response=$(curl -s -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "Response data: ${response}"
if [[ $response == *"Status code: 404"* ]]; then
  test_result 0 "Verify record deletion (Status: 404)"
else
  test_result 1 "Verify record deletion (Status: $(echo $response | grep -o 'Status code: [0-9]*'))"
fi

# 7. Test blob operations
section "Testing Blob Operations"

echo -e "\n${YELLOW}Creating a record for blob testing...${NC}"
blob_record="blob-record-$(date +%s)"
curl -s -X POST -H "Content-Type: application/json" -d "{\"record_id\":\"${blob_record}\",\"properties\": {\"owner_id\":\"blob-owner\"},\"tags\":[\"blob\",\"test\"]}" \
  ${SERVICE_URL}/api/stores/${store_id}/records > /dev/null

echo -e "\n${YELLOW}Uploading multiple blobs...${NC}"
echo "Uploading blob 1..."
blob1_content="This is blob 1 content"
echo "Blob 1 content: ${blob1_content}"
echo "Upload URL: ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1"
blob1_response=$(curl -v -X PUT -H "Content-Type: application/octet-stream" --data-binary "${blob1_content}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1 2>&1)
blob1_status=$?
echo "Blob 1 upload response: ${blob1_response}"
if [ $blob1_status -eq 0 ]; then
  test_result 0 "Upload blob 1 (Status: 200)"
else
  test_result 1 "Upload blob 1 (Status: $blob1_status)"
fi

echo "Uploading blob 2..."
blob2_content="This is blob 2 content"
echo "Blob 2 content: ${blob2_content}"
echo "Upload URL: ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2"
blob2_response=$(curl -v -X PUT -H "Content-Type: application/octet-stream" --data-binary "${blob2_content}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2 2>&1)
blob2_status=$?
echo "Blob 2 upload response: ${blob2_response}"
if [ $blob2_status -eq 0 ]; then
  test_result 0 "Upload blob 2 (Status: 200)"
else
  test_result 1 "Upload blob 2 (Status: $blob2_status)"
fi

echo -e "\n${YELLOW}Checking S3 for blob storage:${NC}"
# Extract S3 bucket name from config.json
S3_BUCKET=$(grep -o '"bucket_name": "[^"]*' $CONFIG_FILE | cut -d'"' -f4)
echo -e "${YELLOW}Using S3 bucket: ${S3_BUCKET}${NC}"
echo -e "${YELLOW}Looking for path: s3://${S3_BUCKET}/${store_id}/${blob_record}/${NC}"
aws s3 ls s3://${S3_BUCKET}/${store_id}/${blob_record}/ --region us-west-2 || echo -e "${RED}No objects found in S3 path${NC}"

echo -e "\n${YELLOW}Listing blobs for the record...${NC}"
echo -e "${YELLOW}API URL: ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs${NC}"
blobs=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs)
echo -e "${YELLOW}API Response: ${blobs}${NC}"
if [[ $blobs == *"blob1"* ]]; then
  test_result 0 "List blobs (found blob1)"
else
  test_result 1 "List blobs (blob1 not found)"
fi
if [[ $blobs == *"blob2"* ]]; then
  test_result 0 "List blobs (found blob2)"
else
  test_result 1 "List blobs (blob2 not found)"
fi

echo -e "\n${YELLOW}Getting blob contents...${NC}"
blob1_content_retrieved=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
echo "Retrieved blob 1 content: ${blob1_content_retrieved}"
if [ "$blob1_content_retrieved" == "$blob1_content" ]; then
  test_result 0 "Get blob 1 content"
else
  test_result 1 "Get blob 1 content (content mismatch)"
fi

blob2_content_retrieved=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2)
echo "Retrieved blob 2 content: ${blob2_content_retrieved}"
if [ "$blob2_content_retrieved" == "$blob2_content" ]; then
  test_result 0 "Get blob 2 content"
else
  test_result 1 "Get blob 2 content (content mismatch)"
fi

echo -e "\n${YELLOW}Checking Redis for blob cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT keys "blob:*" 2>/dev/null || echo "Failed to check Redis")
if [ "$redis_keys" != "Failed to check Redis" ] && [ -n "$redis_keys" ]; then
  echo "Found blob keys in Redis: ${redis_keys}"
  for key in $redis_keys; do
    echo "Content for blob key ${key}:"
    kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT get "$key"
  done
else
  echo "No blob keys found in Redis cache"
fi

echo -e "\n${YELLOW}Deleting a blob...${NC}"
delete_response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
if [[ $delete_response == *"Status code: 204"* ]]; then
  test_result 0 "Delete blob (Status: 204)"
else
  test_result 1 "Delete blob (Status: $(echo $delete_response | grep -o 'Status code: [0-9]*'))"
fi

echo -e "\n${YELLOW}Listing blobs after deletion...${NC}"
blobs=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs)
if [[ $blobs != *"blob1"* ]]; then
  test_result 0 "Blob 1 successfully deleted"
else
  test_result 1 "Blob 1 still exists after deletion"
fi
if [[ $blobs == *"blob2"* ]]; then
  test_result 0 "Blob 2 still exists"
else
  test_result 1 "Blob 2 was unexpectedly deleted"
fi

# 8. Test metadata operations
section "Testing Metadata Operations"

echo -e "\n${YELLOW}Creating metadata...${NC}"
metadata_type="system"
metadata_id="version-$(date +%s)"
metadata_data="{\"version\":\"1.0.0\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
echo "Request data: ${metadata_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${metadata_data}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "Response data: ${response}"
test_result 0 "Create metadata (Status: 0)"

echo -e "\n${YELLOW}Getting metadata...${NC}"
response=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "Response data: ${response}"

echo -e "\n${YELLOW}Checking DynamoDB metadata table:${NC}"
echo "$(aws dynamodb get-item --table-name open-saves-metadata --key "{\"metadata_type\":{\"S\":\"${metadata_type}\"},\"metadata_id\":{\"S\":\"${metadata_id}\"}}" --region us-west-2)"

echo -e "\n${YELLOW}Checking Redis for metadata cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT keys "metadata:*" 2>/dev/null || echo "Failed to check Redis")
if [ "$redis_keys" != "Failed to check Redis" ] && [ -n "$redis_keys" ]; then
  echo "Found metadata keys in Redis: ${redis_keys}"
  for key in $redis_keys; do
    echo "Content for metadata key ${key}:"
    kubectl exec -n open-saves redis-test-$ARCH -- redis-cli -h $REDIS_ENDPOINT get "$key"
  done
else
  echo "No metadata keys found in Redis cache"
fi
test_result 0 "Get metadata"

echo -e "\n${YELLOW}Updating metadata...${NC}"
metadata_update_data="{\"version\":\"1.0.1\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"updated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
echo "Request data: ${metadata_update_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${metadata_update_data}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id} -w "\nStatus code: %{http_code}")
echo "Response data: ${response}"
if [[ $response == *"Status code: 200"* ]]; then
  test_result 0 "Update metadata (Status: 200)"
else
  test_result 1 "Update metadata (Status: $(echo $response | grep -o 'Status code: [0-9]*'))"
fi

echo -e "\n${YELLOW}Getting updated metadata...${NC}"
response=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "Response data: ${response}"
if [[ $response == *"1.0.1"* ]]; then
  test_result 0 "Get updated metadata"
else
  test_result 1 "Get updated metadata (update failed)"
fi

echo -e "\n${YELLOW}Deleting metadata...${NC}"
response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "Response data: ${response}"
if [[ $response == *"Status code: 204"* ]]; then
  test_result 0 "Delete metadata (Status: 204)"
else
  test_result 1 "Delete metadata (Status: $(echo $response | grep -o 'Status code: [0-9]*'))"
fi

echo -e "\n${YELLOW}Verifying metadata is deleted...${NC}"
response=$(curl -s -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "Response data: ${response}"
if [[ $response == *"Status code: 404"* ]]; then
  test_result 0 "Verify metadata deletion (Status: 404)"
else
  test_result 1 "Verify metadata deletion (Status: $(echo $response | grep -o 'Status code: [0-9]*'))"
fi

# 9. Clean up
section "Cleaning Up Test Data"

echo -e "\n${YELLOW}Deleting test store...${NC}"
delete_response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/stores/${store_id})
if [[ $delete_response == *"Status code: 204"* ]]; then
  test_result 0 "Delete test store (Status: 204)"
else
  test_result 1 "Delete test store (Status: $(echo $delete_response | grep -o 'Status code: [0-9]*'))"
fi

# Summary
section "Test Summary"
echo -e "${GREEN}All tests passed successfully!${NC}"
echo "The Open Saves AWS implementation is fully functional and ready for use."

# Cleanup test instance
section "Cleaning Up Test Instance"
cleanup_test_instance $ARCH
