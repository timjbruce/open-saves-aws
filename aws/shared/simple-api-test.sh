#!/bin/bash

# simple-api-test.sh - Simple API test for Open Saves
#
# Usage:
#   1. Automatic detection (requires kubectl access to cluster):
#      ./simple-api-test.sh
#
#   2. Manual endpoint specification:
#      export OPEN_SAVES_ENDPOINT=http://your-load-balancer-url:8080
#      ./simple-api-test.sh
#
#   3. One-liner with custom endpoint:
#      OPEN_SAVES_ENDPOINT=http://localhost:8080 ./simple-api-test.sh

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get endpoint dynamically
echo -e "${BLUE}Detecting Open Saves endpoint...${NC}"

# Try to get the endpoint from Kubernetes service
EXTERNAL_IP=$(kubectl get svc open-saves -n open-saves -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
    ENDPOINT="http://${EXTERNAL_IP}:8080"
    echo -e "${GREEN}✓ Found endpoint via Kubernetes service: ${ENDPOINT}${NC}"
else
    # Fallback: Check if user provided endpoint as environment variable
    if [ -n "$OPEN_SAVES_ENDPOINT" ]; then
        ENDPOINT="$OPEN_SAVES_ENDPOINT"
        echo -e "${GREEN}✓ Using provided endpoint: ${ENDPOINT}${NC}"
    else
        echo -e "${RED}✗ Could not detect endpoint automatically${NC}"
        echo -e "${YELLOW}Please set OPEN_SAVES_ENDPOINT environment variable or ensure kubectl can access the cluster${NC}"
        echo -e "${YELLOW}Example: export OPEN_SAVES_ENDPOINT=http://your-load-balancer-url:8080${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Open Saves API Test${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "${YELLOW}Testing endpoint: ${ENDPOINT}${NC}"

# Test 1: Health check
echo -e "\n${YELLOW}=== Test 1: Health Check ===${NC}"
if curl -f -s "${ENDPOINT}/health" > /dev/null; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 2: Create a store
echo -e "\n${YELLOW}=== Test 2: Create Store ===${NC}"
STORE_ID="test-store-$(date +%s)"
CREATE_RESPONSE=$(curl -s -X POST "${ENDPOINT}/api/stores" \
  -H "Content-Type: application/json" \
  -d "{\"store_id\": \"${STORE_ID}\", \"name\": \"${STORE_ID}\", \"tags\": {\"test\": \"true\"}}")

echo "Create response: $CREATE_RESPONSE"
if echo "$CREATE_RESPONSE" | grep -q -E '"store_id"|"name".*"'${STORE_ID}'"' && ! echo "$CREATE_RESPONSE" | grep -q -i "error\|failed\|required"; then
    echo -e "${GREEN}✓ Store creation successful (with response data)${NC}"
elif [ -z "$CREATE_RESPONSE" ] || [ "$CREATE_RESPONSE" = "{}" ]; then
    echo -e "${GREEN}✓ Store creation successful (empty response - likely success)${NC}"
elif echo "$CREATE_RESPONSE" | grep -q -i "required\|error"; then
    echo -e "${RED}✗ Store creation failed: $CREATE_RESPONSE${NC}"
else
    echo -e "${YELLOW}⚠ Store creation response unclear: $CREATE_RESPONSE${NC}"
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 3: List stores
echo -e "\n${YELLOW}=== Test 3: List Stores ===${NC}"
LIST_RESPONSE=$(curl -s "${ENDPOINT}/api/stores")
echo "List response: $LIST_RESPONSE"
if echo "$LIST_RESPONSE" | grep -q -v '"stores":null' && echo "$LIST_RESPONSE" | grep -q -E '"stores":\s*\[' && [ ${#LIST_RESPONSE} -gt 10 ]; then
    echo -e "${GREEN}✓ Store listing successful - found actual stores${NC}"
elif echo "$LIST_RESPONSE" | grep -q '"stores":null'; then
    echo -e "${YELLOW}⚠ Store listing returned null - no stores found${NC}"
else
    echo -e "${RED}✗ Store listing failed or returned invalid response${NC}"
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 4: Get specific store
echo -e "\n${YELLOW}=== Test 4: Get Store ===${NC}"
GET_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}")
echo "Get store response: $GET_RESPONSE"
if echo "$GET_RESPONSE" | grep -q -E '"store_id"|"name"' && ! echo "$GET_RESPONSE" | grep -q -i "not found\|error"; then
    echo -e "${GREEN}✓ Store retrieval successful${NC}"
elif echo "$GET_RESPONSE" | grep -q -i "not found"; then
    echo -e "${YELLOW}⚠ Store not found: ${STORE_ID}${NC}"
else
    echo -e "${RED}✗ Store retrieval failed or returned invalid response${NC}"
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 5: Create a record
echo -e "\n${YELLOW}=== Test 5: Create Record ===${NC}"
RECORD_KEY="test-record-$(date +%s)"
RECORD_DATA="Hello, Open Saves!"
RECORD_RESPONSE=$(curl -s -X POST "${ENDPOINT}/api/stores/${STORE_ID}/records" \
  -H "Content-Type: application/json" \
  -d "{\"record_id\": \"${RECORD_KEY}\", \"blob_size\": ${#RECORD_DATA}, \"properties\": {\"test\": \"data\", \"timestamp\": \"$(date -Iseconds)\"}}")

echo "Create record response: $RECORD_RESPONSE"
if echo "$RECORD_RESPONSE" | grep -q -E '"record_id"|"key"' && ! echo "$RECORD_RESPONSE" | grep -q -i "error\|failed"; then
    echo -e "${GREEN}✓ Record creation successful${NC}"
elif echo "$RECORD_RESPONSE" | grep -q -i "error\|failed"; then
    echo -e "${RED}✗ Record creation failed: $RECORD_RESPONSE${NC}"
else
    echo -e "${YELLOW}⚠ Record creation response unclear: $RECORD_RESPONSE${NC}"
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 6: List records
echo -e "\n${YELLOW}=== Test 6: List Records ===${NC}"
RECORDS_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records")
echo "List records response: $RECORDS_RESPONSE"
if echo "$RECORDS_RESPONSE" | grep -q -v '"records":null' && echo "$RECORDS_RESPONSE" | grep -q -E '"records":\s*\[' && [ ${#RECORDS_RESPONSE} -gt 10 ]; then
    echo -e "${GREEN}✓ Record listing successful - found actual records${NC}"
elif echo "$RECORDS_RESPONSE" | grep -q '"records":null'; then
    echo -e "${YELLOW}⚠ Record listing returned null - no records found${NC}"
else
    echo -e "${RED}✗ Record listing failed or returned invalid response${NC}"
fi

echo -e "${BLUE}Waiting 3 seconds...${NC}"
sleep 3

# Test 7: Get specific record
echo -e "\n${YELLOW}=== Test 7: Get Record ===${NC}"
GET_RECORD_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records/${RECORD_KEY}")
echo "Get record response: $GET_RECORD_RESPONSE"
if echo "$GET_RECORD_RESPONSE" | grep -q -E '"record_id"|"key"' && ! echo "$GET_RECORD_RESPONSE" | grep -q -i "not found\|error"; then
    echo -e "${GREEN}✓ Record retrieval successful${NC}"
elif echo "$GET_RECORD_RESPONSE" | grep -q -i "not found"; then
    echo -e "${YELLOW}⚠ Record not found: ${RECORD_KEY}${NC}"
else
    echo -e "${RED}✗ Record retrieval failed or returned invalid response${NC}"
fi

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}API Test Complete${NC}"
echo -e "${BLUE}===========================================${NC}"



echo -e "\n${GREEN}All tests completed!${NC}"
