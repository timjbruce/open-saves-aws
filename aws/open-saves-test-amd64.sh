#!/bin/bash
# open-saves-test.sh - Comprehensive test script for Open Saves AWS implementation

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
    exit 1
  fi
}

# 0. Test Redis connectivity
section "Testing Redis Connectivity"
echo -e "${YELLOW}Creating a Redis test pod...${NC}"
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: redis-test
  namespace: open-saves
spec:
  containers:
  - name: redis-test
    image: redis:alpine
    command: ["sleep", "300"]
  nodeSelector:
    kubernetes.io/arch: arm64
EOF

echo -e "${YELLOW}Waiting for Redis test pod to be ready...${NC}"
kubectl wait --for=condition=Ready pod/redis-test -n open-saves --timeout=60s

# Get Redis endpoint from config
echo -e "${YELLOW}Getting Redis endpoint from config...${NC}"
REDIS_ENDPOINT=$(kubectl get configmap -n open-saves open-saves-config -o yaml | grep address | awk -F'"' '{print $2}')
echo -e "${YELLOW}Redis endpoint: ${REDIS_ENDPOINT}${NC}"

# Test Redis connectivity
echo -e "${YELLOW}Testing Redis connectivity...${NC}"
REDIS_PING=$(kubectl exec -n open-saves redis-test -- redis-cli -h $(echo $REDIS_ENDPOINT | cut -d':' -f1) ping)
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
kubectl exec -n open-saves redis-test -- redis-cli -h $(echo $REDIS_ENDPOINT | cut -d':' -f1) set $TEST_KEY $TEST_VALUE
READ_VALUE=$(kubectl exec -n open-saves redis-test -- redis-cli -h $(echo $REDIS_ENDPOINT | cut -d':' -f1) get $TEST_KEY)
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
echo -e "Request data: ${store_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${store_data}" ${SERVICE_URL}/api/stores)
status_code=$?
echo -e "Response data: ${response}"
test_result $([[ $status_code -eq 0 ]] && echo 0 || echo 1) "Create store (Status: ${status_code})"

echo -e "\n${YELLOW}Listing stores...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores)
echo -e "Response data: ${response}"
echo "$response" | grep -q "${store_id}"
test_result $? "List stores (found ${store_id})"

echo -e "\n${YELLOW}Getting store...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id})
echo -e "Response data: ${response}"
echo "$response" | grep -q "${store_id}"
test_result $? "Get store (found ${store_id})"

# 3. Test record operations
section "Testing Record Operations"

echo -e "\n${YELLOW}Creating a test record...${NC}"
record_id="test-record-$(date +%s)"
record_data="{\"record_id\":\"${record_id}\",\"owner_id\":\"test-owner\",\"tags\":[\"test\",\"demo\"],\"properties\":{\"score\":100,\"level\":5}}"
echo -e "Request data: ${record_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${record_data}" ${SERVICE_URL}/api/stores/${store_id}/records)
status_code=$?
echo -e "Response data: ${response}"
test_result $([[ $status_code -eq 0 ]] && echo 0 || echo 1) "Create record (Status: ${status_code})"

echo -e "\n${YELLOW}Getting record...${NC}"
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id})
echo -e "Response data: ${response}"
echo "$response" | grep -q "${record_id}"
test_result $? "Get record (found ${record_id})"

# 4. Test Redis caching performance
section "Testing Redis Caching Performance"

echo -e "\n${YELLOW}Testing store retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id})
echo -e "Response data: ${response}"

# Check DynamoDB stores table
echo -e "\n${YELLOW}Checking DynamoDB stores table:${NC}"
dynamo_response=$(aws dynamodb get-item --table-name open-saves-stores --key "{\"store_id\":{\"S\":\"${store_id}\"}}" --region us-west-2 --output json)
echo -e "DynamoDB response: ${dynamo_response}"

echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
echo -e "First request: ${time_first}s, Second request: ${time_second}s"

# Check Redis for store cache entry
echo -e "\n${YELLOW}Checking Redis for store cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com keys "*${store_id}*" 2>/dev/null || echo "Failed to check Redis")
echo -e "Redis keys: ${redis_keys}"
if [ ! -z "$redis_keys" ]; then
  echo "Found keys in Redis: $redis_keys"
  for key in $redis_keys; do
    redis_value=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com get "$key" 2>/dev/null || echo "Failed to get Redis key")
    echo "Content for key $key:"
    echo "$redis_value"
  done
else
  echo "No store keys found in Redis cache"
fi

echo -e "\n${YELLOW}Testing record retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
response=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id})
echo -e "Response data: ${response}"

# Check DynamoDB records table
echo -e "\n${YELLOW}Checking DynamoDB records table:${NC}"
dynamo_response=$(aws dynamodb get-item --table-name open-saves-records --key "{\"store_id\":{\"S\":\"${store_id}\"},\"record_id\":{\"S\":\"${record_id}\"}}" --region us-west-2 --output json)
echo -e "DynamoDB response: ${dynamo_response}"

echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
echo -e "First request: ${time_first}s, Second request: ${time_second}s"

# Check Redis for record cache entry
echo -e "\n${YELLOW}Checking Redis for record cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com keys "*${record_id}*" 2>/dev/null || echo "Failed to check Redis")
echo -e "Redis keys: ${redis_keys}"
if [ ! -z "$redis_keys" ]; then
  echo "Found keys in Redis: $redis_keys"
  for key in $redis_keys; do
    redis_value=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com get "$key" 2>/dev/null || echo "Failed to get Redis key")
    echo "Content for key $key:"
    echo "$redis_value"
  done
else
  echo "No record keys found in Redis cache"
fi

# 5. Test query operations
section "Testing Query Operations"

echo -e "\n${YELLOW}Creating multiple records with the same owner...${NC}"
query_owner="query-owner-$(date +%s)"
for i in {1..3}; do
  query_record="query-record-$i-$(date +%s)"
  curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"record_id\":\"${query_record}\",\"owner_id\":\"${query_owner}\",\"tags\":[\"query\",\"test\"],\"properties\":{\"score\":$((i*10)),\"level\":$i}}" \
    ${SERVICE_URL}/api/stores/${store_id}/records > /dev/null
done

echo -e "\n${YELLOW}Querying records by owner...${NC}"
query_result=$(curl -s "${SERVICE_URL}/api/stores/${store_id}/records?owner_id=${query_owner}")
echo -e "Response data: ${query_result}"
record_count=$(echo "$query_result" | grep -o "record_id" | wc -l)
test_result $([[ $record_count -eq 3 ]] && echo 0 || echo 1) "Query by owner (found ${record_count} records)"

# 6. Test update and delete operations
section "Testing Update and Delete Operations"

echo -e "\n${YELLOW}Creating a record to update...${NC}"
update_record="update-record-$(date +%s)"
update_create_data="{\"record_id\":\"${update_record}\",\"owner_id\":\"update-owner\",\"tags\":[\"update\",\"test\"],\"properties\":{\"score\":50,\"level\":5}}"
echo -e "Request data: ${update_create_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${update_create_data}" ${SERVICE_URL}/api/stores/${store_id}/records)
echo -e "Response data: ${response}"

echo -e "\n${YELLOW}Getting the record before update...${NC}"
before_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo -e "Response data: ${before_update}"
echo "$before_update" | grep -q "update-owner"
test_result $? "Get record before update"

echo -e "\n${YELLOW}Updating the record...${NC}"
update_data="{\"owner_id\":\"updated-owner\",\"tags\":[\"updated\",\"test\"],\"properties\":{\"score\":100,\"level\":10}}"
echo -e "Request data: ${update_data}"
response=$(curl -s -X PUT -H "Content-Type: application/json" -d "${update_data}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
status_code=$?
echo -e "Response data: ${response}"
test_result $([[ $status_code -eq 0 ]] && echo 0 || echo 1) "Update record (Status: ${status_code})"

echo -e "\n${YELLOW}Getting the record after update...${NC}"
after_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo -e "Response data: ${after_update}"
echo "$after_update" | grep -q "updated-owner"
test_result $? "Get record after update"

echo -e "\n${YELLOW}Deleting the record...${NC}"
response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo -e "Response data: ${response}"
status_code=$(echo "$response" | grep -o "Status code: [0-9]*" | cut -d' ' -f3)
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete record (Status: ${status_code})"

echo -e "\n${YELLOW}Verifying the record is deleted...${NC}"
response=$(curl -s -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo -e "Response data: ${response}"
status_code=$(echo "$response" | grep -o "Status code: [0-9]*" | cut -d' ' -f3)
test_result $([[ $status_code -eq 404 ]] && echo 0 || echo 1) "Verify record deletion (Status: ${status_code})"

# 7. Test blob operations
section "Testing Blob Operations"

echo -e "\n${YELLOW}Creating a record for blob testing...${NC}"
blob_record="blob-record-$(date +%s)"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"record_id\":\"${blob_record}\",\"owner_id\":\"blob-owner\",\"tags\":[\"blob\",\"test\"],\"properties\":{\"test\":true}}" \
  ${SERVICE_URL}/api/stores/${store_id}/records > /dev/null

echo -e "\n${YELLOW}Uploading multiple blobs...${NC}"
echo "Uploading blob 1..."
blob1_content="This is blob 1 content"
echo -e "Blob 1 content: ${blob1_content}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/octet-stream" \
  --data-binary "${blob1_content}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Upload blob 1 (Status: ${status_code})"

echo "Uploading blob 2..."
blob2_content="This is blob 2 content"
echo -e "Blob 2 content: ${blob2_content}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/octet-stream" \
  --data-binary "${blob2_content}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2)
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Upload blob 2 (Status: ${status_code})"

# Check S3 for blob storage
echo -e "\n${YELLOW}Checking S3 for blob storage:${NC}"
aws s3 ls s3://open-saves-blobs-992265960412/${store_id}/${blob_record}/ || echo "Failed to list S3 objects"

echo -e "\n${YELLOW}Listing blobs for the record...${NC}"
blobs=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs)
echo "$blobs" | grep -q "blob1"
test_result $? "List blobs (found blob1)"
echo "$blobs" | grep -q "blob2"
test_result $? "List blobs (found blob2)"

echo -e "\n${YELLOW}Getting blob contents...${NC}"
blob1_content_retrieved=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
echo -e "Retrieved blob 1 content: ${blob1_content_retrieved}"
[[ "$blob1_content_retrieved" == "${blob1_content}" ]]
test_result $? "Get blob 1 content"

blob2_content_retrieved=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2)
echo -e "Retrieved blob 2 content: ${blob2_content_retrieved}"
[[ "$blob2_content_retrieved" == "${blob2_content}" ]]
test_result $? "Get blob 2 content"

# Check Redis for blob cache entry
echo -e "\n${YELLOW}Checking Redis for blob cache entry:${NC}"
kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com keys "*blob*" || echo "Failed to check Redis"
blob_keys=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com keys "*blob*" 2>/dev/null)
if [ ! -z "$blob_keys" ]; then
  echo "Found keys in Redis: $blob_keys"
  for key in $blob_keys; do
    echo "Content for key $key:"
    kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com get "$key" || echo "Failed to get Redis key"
  done
else
  echo "No blob keys found in Redis cache"
fi

echo -e "\n${YELLOW}Deleting a blob...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete blob (Status: ${status_code})"

echo -e "\n${YELLOW}Listing blobs after deletion...${NC}"
blobs=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs)
echo "$blobs" | grep -q "blob1"
if [ $? -eq 0 ]; then
  test_result 1 "Blob 1 should be deleted but was found"
else
  test_result 0 "Blob 1 successfully deleted"
fi
echo "$blobs" | grep -q "blob2"
test_result $? "Blob 2 still exists"

# 8. Test metadata operations
section "Testing Metadata Operations"

metadata_type="system"
metadata_id="version-$(date +%s)"

echo -e "\n${YELLOW}Creating metadata...${NC}"
metadata_data="{\"version\":\"1.0.0\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
echo -e "Request data: ${metadata_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${metadata_data}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
status_code=$?
echo -e "Response data: ${response}"
test_result $([[ $status_code -eq 0 ]] && echo 0 || echo 1) "Create metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Getting metadata...${NC}"
response=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo -e "Response data: ${response}"

# Check DynamoDB metadata table
echo -e "\n${YELLOW}Checking DynamoDB metadata table:${NC}"
aws dynamodb get-item --table-name open-saves-metadata --key "{\"metadata_type\":{\"S\":\"${metadata_type}\"},\"metadata_id\":{\"S\":\"${metadata_id}\"}}" --region us-west-2 --output json | jq . || echo "Failed to get metadata from DynamoDB"

# Check Redis for metadata cache entry
echo -e "\n${YELLOW}Checking Redis for metadata cache entry:${NC}"
redis_keys=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com keys "*${metadata_id}*" 2>/dev/null || echo "Failed to check Redis")
echo -e "Redis keys: ${redis_keys}"
if [ ! -z "$redis_keys" ] && [ "$redis_keys" != "Failed to check Redis" ]; then
  echo "Found keys in Redis: $redis_keys"
  for key in $redis_keys; do
    redis_value=$(kubectl exec -n open-saves network-debug -- redis-cli -h open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com get "$key" 2>/dev/null || echo "Failed to get Redis key")
    echo "Content for key $key:"
    echo "$redis_value"
  done
else
  echo "No metadata keys found in Redis cache"
fi

echo "$response" | grep -q "1.0.0"
test_result $? "Get metadata"

echo -e "\n${YELLOW}Updating metadata...${NC}"
metadata_update_data="{\"version\":\"1.0.1\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"updated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
echo -e "Request data: ${metadata_update_data}"
response=$(curl -s -X POST -H "Content-Type: application/json" -d "${metadata_update_data}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id} -w "\nStatus code: %{http_code}")
echo -e "Response data: ${response}"
status_code=$(echo "$response" | grep -o "Status code: [0-9]*" | cut -d' ' -f3)
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Update metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Getting updated metadata...${NC}"
response=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo -e "Response data: ${response}"
echo "$response" | grep -q "1.0.1"
test_result $? "Get updated metadata"

echo -e "\n${YELLOW}Deleting metadata...${NC}"
response=$(curl -s -X DELETE -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo -e "Response data: ${response}"
status_code=$(echo "$response" | grep -o "Status code: [0-9]*" | cut -d' ' -f3)
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Verifying metadata is deleted...${NC}"
response=$(curl -s -w "\nStatus code: %{http_code}" ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo -e "Response data: ${response}"
status_code=$(echo "$response" | grep -o "Status code: [0-9]*" | cut -d' ' -f3)
test_result $([[ $status_code -eq 404 ]] && echo 0 || echo 1) "Verify metadata deletion (Status: ${status_code})"

# 9. Clean up
section "Cleaning Up Test Data"

echo -e "\n${YELLOW}Deleting test store...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  ${SERVICE_URL}/api/stores/${store_id})
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete test store (Status: ${status_code})"

# Final summary
section "Test Summary"
echo -e "${GREEN}All tests passed successfully!${NC}"
echo -e "The Open Saves AWS implementation is fully functional and ready for use."
