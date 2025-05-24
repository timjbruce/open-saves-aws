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
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d "{\"store_id\":\"${store_id}\",\"name\":\"Test Store\"}" \
  ${SERVICE_URL}/api/stores)
test_result $([[ $status_code -eq 201 ]] && echo 0 || echo 1) "Create store (Status: ${status_code})"

echo -e "\n${YELLOW}Listing stores...${NC}"
stores=$(curl -s ${SERVICE_URL}/api/stores)
echo "$stores" | grep -q "${store_id}"
test_result $? "List stores (found ${store_id})"

echo -e "\n${YELLOW}Getting store...${NC}"
store=$(curl -s ${SERVICE_URL}/api/stores/${store_id})
echo "$store" | grep -q "${store_id}"
test_result $? "Get store (found ${store_id})"

# 3. Test record operations
section "Testing Record Operations"

echo -e "\n${YELLOW}Creating a test record...${NC}"
record_id="test-record-$(date +%s)"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d "{\"record_id\":\"${record_id}\",\"owner_id\":\"test-owner\",\"tags\":[\"test\",\"demo\"],\"properties\":{\"score\":100,\"level\":5}}" \
  ${SERVICE_URL}/api/stores/${store_id}/records)
test_result $([[ $status_code -eq 201 ]] && echo 0 || echo 1) "Create record (Status: ${status_code})"

echo -e "\n${YELLOW}Getting record...${NC}"
record=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id})
echo "$record" | grep -q "${record_id}"
test_result $? "Get record (found ${record_id})"

# 4. Test Redis caching performance
section "Testing Redis Caching Performance"

echo -e "\n${YELLOW}Testing store retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id} > /dev/null; } 2>&1)
echo -e "First request: ${time_first}s, Second request: ${time_second}s"

echo -e "\n${YELLOW}Testing record retrieval performance...${NC}"
echo "First request (should hit DynamoDB):"
time_first=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
echo "Second request (should hit Redis cache):"
time_second=$(TIMEFORMAT='%3R'; { time curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${record_id} > /dev/null; } 2>&1)
echo -e "First request: ${time_first}s, Second request: ${time_second}s"

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
record_count=$(echo "$query_result" | grep -o "record_id" | wc -l)
test_result $([[ $record_count -eq 3 ]] && echo 0 || echo 1) "Query by owner (found ${record_count} records)"

# 6. Test update and delete operations
section "Testing Update and Delete Operations"

echo -e "\n${YELLOW}Creating a record to update...${NC}"
update_record="update-record-$(date +%s)"
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"record_id\":\"${update_record}\",\"owner_id\":\"update-owner\",\"tags\":[\"update\",\"test\"],\"properties\":{\"score\":50,\"level\":5}}" \
  ${SERVICE_URL}/api/stores/${store_id}/records > /dev/null

echo -e "\n${YELLOW}Getting the record before update...${NC}"
before_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "$before_update" | grep -q "update-owner"
test_result $? "Get record before update"

echo -e "\n${YELLOW}Updating the record...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/json" \
  -d "{\"owner_id\":\"updated-owner\",\"tags\":[\"updated\",\"test\"],\"properties\":{\"score\":100,\"level\":10}}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Update record (Status: ${status_code})"

echo -e "\n${YELLOW}Getting the record after update...${NC}"
after_update=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
echo "$after_update" | grep -q "updated-owner"
test_result $? "Get record after update"

echo -e "\n${YELLOW}Deleting the record...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete record (Status: ${status_code})"

echo -e "\n${YELLOW}Verifying the record is deleted...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${update_record})
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
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/octet-stream" \
  --data-binary "This is blob 1 content" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Upload blob 1 (Status: ${status_code})"

echo "Uploading blob 2..."
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Content-Type: application/octet-stream" \
  --data-binary "This is blob 2 content" \
  ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2)
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Upload blob 2 (Status: ${status_code})"

echo -e "\n${YELLOW}Listing blobs for the record...${NC}"
blobs=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs)
echo "$blobs" | grep -q "blob1"
test_result $? "List blobs (found blob1)"
echo "$blobs" | grep -q "blob2"
test_result $? "List blobs (found blob2)"

echo -e "\n${YELLOW}Getting blob contents...${NC}"
blob1_content=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob1)
[[ "$blob1_content" == "This is blob 1 content" ]]
test_result $? "Get blob 1 content"

blob2_content=$(curl -s ${SERVICE_URL}/api/stores/${store_id}/records/${blob_record}/blobs/blob2)
[[ "$blob2_content" == "This is blob 2 content" ]]
test_result $? "Get blob 2 content"

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
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d "{\"version\":\"1.0.0\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" \
  ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Create metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Getting metadata...${NC}"
metadata=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "$metadata" | grep -q "1.0.0"
test_result $? "Get metadata"

echo -e "\n${YELLOW}Updating metadata...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
  -d "{\"version\":\"1.0.1\",\"created_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"updated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" \
  ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
test_result $([[ $status_code -eq 200 ]] && echo 0 || echo 1) "Update metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Getting updated metadata...${NC}"
metadata=$(curl -s ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
echo "$metadata" | grep -q "1.0.1"
test_result $? "Get updated metadata"

echo -e "\n${YELLOW}Deleting metadata...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
test_result $([[ $status_code -eq 204 ]] && echo 0 || echo 1) "Delete metadata (Status: ${status_code})"

echo -e "\n${YELLOW}Verifying metadata is deleted...${NC}"
status_code=$(curl -s -o /dev/null -w "%{http_code}" \
  ${SERVICE_URL}/api/metadata/${metadata_type}/${metadata_id})
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
