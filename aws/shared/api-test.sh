#!/bin/bash

# api-test.sh - Unified API test script for Open Saves
#
# This script tests the Open Saves API endpoints and works with any backend
# implementation (DynamoDB, DocumentDB, etc.) since it only tests the API layer.
# 
# Tests include:
#   1. Health Check
#   2. Store Creation
#   3. Store Listing  
#   4. Store Retrieval
#   5. Record Creation
#   6. Record Listing
#   7. Record Retrieval
#   8. Blob Record Creation
#   9. Blob Data Upload
#   10. Blob Listing
#   11. Blob Data Retrieval & Verification
#
# Usage:
#   1. Automatic endpoint detection (requires kubectl access to cluster):
#      ./api-test.sh
#
#   2. Manual endpoint specification:
#      export OPEN_SAVES_ENDPOINT=http://your-load-balancer-url:8080
#      ./api-test.sh
#
#   3. One-liner with custom endpoint:
#      OPEN_SAVES_ENDPOINT=http://localhost:8080 ./api-test.sh
#
#   4. Specify architecture for endpoint detection:
#      ./api-test.sh --architecture arm64
#      ./api-test.sh --architecture amd64

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ARCHITECTURE=""
NAMESPACE="open-saves"
SERVICE_NAME="open-saves"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --architecture)
            ARCHITECTURE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --architecture ARCH    Specify architecture (arm64/amd64) for context"
            echo "  --namespace NS         Kubernetes namespace (default: open-saves)"
            echo "  --service NAME         Service name (default: open-saves)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to detect endpoint dynamically
detect_endpoint() {
    echo -e "${BLUE}Detecting Open Saves endpoint...${NC}"
    
    # Try to get the endpoint from Kubernetes service
    EXTERNAL_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
        ENDPOINT="http://${EXTERNAL_IP}:8080"
        echo -e "${GREEN}✓ Found endpoint via Kubernetes service: ${ENDPOINT}${NC}"
        return 0
    fi
    
    # Fallback: Check if user provided endpoint as environment variable
    if [ -n "$OPEN_SAVES_ENDPOINT" ]; then
        ENDPOINT="$OPEN_SAVES_ENDPOINT"
        echo -e "${GREEN}✓ Using provided endpoint: ${ENDPOINT}${NC}"
        return 0
    fi
    
    # Final fallback: Try to detect from kubectl context
    CLUSTER_INFO=$(kubectl cluster-info 2>/dev/null | head -1)
    if [ -n "$CLUSTER_INFO" ]; then
        echo -e "${YELLOW}⚠ Could not detect endpoint automatically${NC}"
        echo -e "${YELLOW}Kubernetes cluster detected but service endpoint not available${NC}"
    else
        echo -e "${YELLOW}⚠ No kubectl access detected${NC}"
    fi
    
    echo -e "${RED}✗ Could not detect endpoint automatically${NC}"
    echo -e "${YELLOW}Please set OPEN_SAVES_ENDPOINT environment variable${NC}"
    echo -e "${YELLOW}Example: export OPEN_SAVES_ENDPOINT=http://your-load-balancer-url:8080${NC}"
    return 1
}

# Function to test API endpoint
test_api() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}Open Saves API Test${NC}"
    if [ -n "$ARCHITECTURE" ]; then
        echo -e "${BLUE}Architecture: ${ARCHITECTURE}${NC}"
    fi
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${YELLOW}Testing endpoint: ${ENDPOINT}${NC}"
    
    # Test 1: Health check
    echo -e "\n${YELLOW}=== Test 1: Health Check ===${NC}"
    if curl -f -s "${ENDPOINT}/health" > /dev/null; then
        echo -e "${GREEN}✓ Health check passed${NC}"
    else
        echo -e "${RED}✗ Health check failed${NC}"
        echo -e "${RED}Cannot proceed with API tests - service is not responding${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 2: Create a store
    echo -e "\n${YELLOW}=== Test 2: Create Store ===${NC}"
    STORE_ID="test-store-$(date +%s)"
    CREATE_RESPONSE=$(curl -s -X POST "${ENDPOINT}/api/stores" \
      -H "Content-Type: application/json" \
      -d "{\"store_id\": \"${STORE_ID}\", \"name\": \"${STORE_ID}\", \"tags\": {\"test\": \"true\", \"backend\": \"any\"}}")
    
    echo "Create response: $CREATE_RESPONSE"
    if echo "$CREATE_RESPONSE" | grep -q -E '"store_id"|"name".*"'${STORE_ID}'"' && ! echo "$CREATE_RESPONSE" | grep -q -i "error\|failed\|required"; then
        echo -e "${GREEN}✓ Store creation successful (with response data)${NC}"
        STORE_CREATED=true
    elif [ -z "$CREATE_RESPONSE" ] || [ "$CREATE_RESPONSE" = "{}" ]; then
        echo -e "${GREEN}✓ Store creation successful (empty response - likely success)${NC}"
        STORE_CREATED=true
    elif echo "$CREATE_RESPONSE" | grep -q -i "required\|error"; then
        echo -e "${RED}✗ Store creation failed: $CREATE_RESPONSE${NC}"
        STORE_CREATED=false
    else
        echo -e "${YELLOW}⚠ Store creation response unclear: $CREATE_RESPONSE${NC}"
        STORE_CREATED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 3: List stores
    echo -e "\n${YELLOW}=== Test 3: List Stores ===${NC}"
    LIST_RESPONSE=$(curl -s "${ENDPOINT}/api/stores")
    echo "List response: $LIST_RESPONSE"
    if echo "$LIST_RESPONSE" | grep -q -v '"stores":null' && echo "$LIST_RESPONSE" | grep -q -E '"stores":\s*\[' && [ ${#LIST_RESPONSE} -gt 10 ]; then
        echo -e "${GREEN}✓ Store listing successful - found actual stores${NC}"
        STORES_FOUND=true
    elif echo "$LIST_RESPONSE" | grep -q '"stores":null'; then
        echo -e "${YELLOW}⚠ Store listing returned null - no stores found${NC}"
        STORES_FOUND=false
    else
        echo -e "${RED}✗ Store listing failed or returned invalid response${NC}"
        STORES_FOUND=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 4: Get specific store
    echo -e "\n${YELLOW}=== Test 4: Get Store ===${NC}"
    GET_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}")
    echo "Get store response: $GET_RESPONSE"
    if echo "$GET_RESPONSE" | grep -q -E '"store_id"|"name"' && ! echo "$GET_RESPONSE" | grep -q -i "not found\|error"; then
        echo -e "${GREEN}✓ Store retrieval successful${NC}"
        STORE_RETRIEVED=true
    elif echo "$GET_RESPONSE" | grep -q -i "not found"; then
        echo -e "${YELLOW}⚠ Store not found: ${STORE_ID}${NC}"
        STORE_RETRIEVED=false
    else
        echo -e "${RED}✗ Store retrieval failed or returned invalid response${NC}"
        STORE_RETRIEVED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 5: Create a record
    echo -e "\n${YELLOW}=== Test 5: Create Record ===${NC}"
    RECORD_KEY="test-record-$(date +%s)"
    RECORD_DATA="Hello, Open Saves! Backend-agnostic test data."
    RECORD_RESPONSE=$(curl -s -X POST "${ENDPOINT}/api/stores/${STORE_ID}/records" \
      -H "Content-Type: application/json" \
      -d "{\"record_id\": \"${RECORD_KEY}\", \"key\": \"${RECORD_KEY}\", \"blob_size\": ${#RECORD_DATA}, \"properties\": {\"test\": \"data\", \"timestamp\": \"$(date -Iseconds)\", \"backend\": \"any\"}}")
    
    echo "Create record response: $RECORD_RESPONSE"
    if echo "$RECORD_RESPONSE" | grep -q -E '"record_id"|"key"' && ! echo "$RECORD_RESPONSE" | grep -q -i "error\|failed"; then
        echo -e "${GREEN}✓ Record creation successful (with response data)${NC}"
        RECORD_CREATED=true
    elif [ -z "$RECORD_RESPONSE" ] || [ "$RECORD_RESPONSE" = "{}" ]; then
        echo -e "${GREEN}✓ Record creation successful (empty response - likely success)${NC}"
        RECORD_CREATED=true
    elif echo "$RECORD_RESPONSE" | grep -q -i "error\|failed\|not found\|required"; then
        echo -e "${RED}✗ Record creation failed: $RECORD_RESPONSE${NC}"
        RECORD_CREATED=false
    else
        echo -e "${YELLOW}⚠ Record creation response unclear: $RECORD_RESPONSE${NC}"
        RECORD_CREATED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 6: List records
    echo -e "\n${YELLOW}=== Test 6: List Records ===${NC}"
    RECORDS_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records")
    echo "List records response: $RECORDS_RESPONSE"
    if echo "$RECORDS_RESPONSE" | grep -q -v '"records":null' && echo "$RECORDS_RESPONSE" | grep -q -E '"records":\s*\[' && [ ${#RECORDS_RESPONSE} -gt 10 ]; then
        echo -e "${GREEN}✓ Record listing successful - found actual records${NC}"
        RECORDS_FOUND=true
    elif echo "$RECORDS_RESPONSE" | grep -q '"records":null'; then
        echo -e "${YELLOW}⚠ Record listing returned null - no records found${NC}"
        RECORDS_FOUND=false
    else
        echo -e "${RED}✗ Record listing failed or returned invalid response${NC}"
        RECORDS_FOUND=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 7: Get specific record
    echo -e "\n${YELLOW}=== Test 7: Get Record ===${NC}"
    GET_RECORD_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records/${RECORD_KEY}")
    echo "Get record response: $GET_RECORD_RESPONSE"
    if echo "$GET_RECORD_RESPONSE" | grep -q -E '"record_id"|"key"' && ! echo "$GET_RECORD_RESPONSE" | grep -q -i "not found\|error"; then
        echo -e "${GREEN}✓ Record retrieval successful${NC}"
        RECORD_RETRIEVED=true
    elif echo "$GET_RECORD_RESPONSE" | grep -q -i "not found"; then
        echo -e "${YELLOW}⚠ Record not found: ${RECORD_KEY}${NC}"
        RECORD_RETRIEVED=false
    else
        echo -e "${RED}✗ Record retrieval failed or returned invalid response${NC}"
        RECORD_RETRIEVED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 8: Update record with PUT
    echo -e "\n${YELLOW}=== Test 8: Update Record (PUT) ===${NC}"
    if [ "$RECORD_RETRIEVED" = true ]; then
        PUT_RESPONSE=$(curl -s -X PUT "${ENDPOINT}/api/stores/${STORE_ID}/records/${RECORD_KEY}" \
          -H "Content-Type: application/json" \
          -d "{\"properties\": {\"updated\": \"true\", \"method\": \"PUT\", \"timestamp\": \"$(date -Iseconds)\"}, \"tags\": [\"updated\", \"test\"]}")
        
        echo "PUT record response: $PUT_RESPONSE"
        if [ -z "$PUT_RESPONSE" ] || [ "$PUT_RESPONSE" = "{}" ]; then
            echo -e "${GREEN}✓ Record update successful (empty response - likely success)${NC}"
            RECORD_UPDATED=true
        elif echo "$PUT_RESPONSE" | grep -q -i "error\|failed\|not found"; then
            echo -e "${RED}✗ Record update failed: $PUT_RESPONSE${NC}"
            RECORD_UPDATED=false
        else
            echo -e "${YELLOW}⚠ Record update response unclear: $PUT_RESPONSE${NC}"
            RECORD_UPDATED=false
        fi
    else
        echo -e "${YELLOW}⚠ Skipping record update - record retrieval failed${NC}"
        RECORD_UPDATED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 9: Verify record was updated
    echo -e "\n${YELLOW}=== Test 9: Verify Record Update ===${NC}"
    if [ "$RECORD_UPDATED" = true ]; then
        UPDATED_RECORD_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records/${RECORD_KEY}")
        echo "Updated record response: $UPDATED_RECORD_RESPONSE"
        
        if echo "$UPDATED_RECORD_RESPONSE" | grep -q '"updated":"true"' && echo "$UPDATED_RECORD_RESPONSE" | grep -q '"method":"PUT"'; then
            echo -e "${GREEN}✓ Record update verification successful - record contains updated data${NC}"
            RECORD_UPDATE_VERIFIED=true
        else
            echo -e "${RED}✗ Record update verification failed - updated data not found${NC}"
            RECORD_UPDATE_VERIFIED=false
        fi
    else
        echo -e "${YELLOW}⚠ Skipping update verification - record update failed${NC}"
        RECORD_UPDATE_VERIFIED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 10: Create a record with blob data
    echo -e "\n${YELLOW}=== Test 8: Create Record with Blob ===${NC}"
    BLOB_RECORD_KEY="blob-record-$(date +%s)"
    
    # Create the record metadata first
    BLOB_RECORD_RESPONSE=$(curl -s -X POST "${ENDPOINT}/api/stores/${STORE_ID}/records" \
      -H "Content-Type: application/json" \
      -d "{\"record_id\": \"${BLOB_RECORD_KEY}\", \"properties\": {\"type\": \"blob\", \"test\": \"binary_data\", \"timestamp\": \"$(date -Iseconds)\", \"backend\": \"any\"}, \"tags\": [\"blob\", \"test\"]}")
    
    echo "Create blob record response: $BLOB_RECORD_RESPONSE"
    if echo "$BLOB_RECORD_RESPONSE" | grep -q -E '"record_id"|"key"' && ! echo "$BLOB_RECORD_RESPONSE" | grep -q -i "error\|failed"; then
        echo -e "${GREEN}✓ Blob record creation successful (with response data)${NC}"
        BLOB_RECORD_CREATED=true
    elif [ -z "$BLOB_RECORD_RESPONSE" ] || [ "$BLOB_RECORD_RESPONSE" = "{}" ]; then
        echo -e "${GREEN}✓ Blob record creation successful (empty response - likely success)${NC}"
        BLOB_RECORD_CREATED=true
    elif echo "$BLOB_RECORD_RESPONSE" | grep -q -i "error\|failed\|not found\|required"; then
        echo -e "${RED}✗ Blob record creation failed: $BLOB_RECORD_RESPONSE${NC}"
        BLOB_RECORD_CREATED=false
    else
        echo -e "${YELLOW}⚠ Blob record creation response unclear: $BLOB_RECORD_RESPONSE${NC}"
        BLOB_RECORD_CREATED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 9: Upload blob data
    echo -e "\n${YELLOW}=== Test 9: Upload Blob Data ===${NC}"
    if [ "$BLOB_RECORD_CREATED" = true ]; then
        BLOB_NAME="test-blob"
        BLOB_DATA="This is test blob data for Open Saves API testing. It contains binary-like content and special characters: éñ中文🚀"
        
        # Create a temporary file with the blob data
        TEMP_BLOB_FILE="/tmp/test_blob_${BLOB_RECORD_KEY}.dat"
        echo -n "$BLOB_DATA" > "$TEMP_BLOB_FILE"
        
        # Upload the blob data using the correct endpoint pattern
        BLOB_ENDPOINT="${ENDPOINT}/api/stores/${STORE_ID}/records/${BLOB_RECORD_KEY}/blobs/${BLOB_NAME}"
        echo "Uploading to: $BLOB_ENDPOINT"
        
        BLOB_UPLOAD_RESPONSE=$(curl -s -X PUT "$BLOB_ENDPOINT" \
          -H "Content-Type: application/octet-stream" \
          --data-binary "@${TEMP_BLOB_FILE}")
        
        echo "Blob upload response: $BLOB_UPLOAD_RESPONSE"
        if [ -z "$BLOB_UPLOAD_RESPONSE" ] || [ "$BLOB_UPLOAD_RESPONSE" = "{}" ] || echo "$BLOB_UPLOAD_RESPONSE" | grep -q -i "success\|uploaded"; then
            echo -e "${GREEN}✓ Blob data upload successful${NC}"
            BLOB_UPLOADED=true
        elif echo "$BLOB_UPLOAD_RESPONSE" | grep -q -i "error\|failed\|404"; then
            echo -e "${RED}✗ Blob data upload failed: $BLOB_UPLOAD_RESPONSE${NC}"
            BLOB_UPLOADED=false
        else
            echo -e "${YELLOW}⚠ Blob upload response unclear: $BLOB_UPLOAD_RESPONSE${NC}"
            BLOB_UPLOADED=false
        fi
        
        # Clean up temp file
        rm -f "$TEMP_BLOB_FILE"
    else
        echo -e "${YELLOW}⚠ Skipping blob upload - record creation failed${NC}"
        BLOB_UPLOADED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 10: List blobs for the record
    echo -e "\n${YELLOW}=== Test 10: List Blobs ===${NC}"
    if [ "$BLOB_RECORD_CREATED" = true ]; then
        BLOBS_LIST_RESPONSE=$(curl -s "${ENDPOINT}/api/stores/${STORE_ID}/records/${BLOB_RECORD_KEY}/blobs")
        echo "List blobs response: $BLOBS_LIST_RESPONSE"
        
        if echo "$BLOBS_LIST_RESPONSE" | grep -q "$BLOB_NAME"; then
            echo -e "${GREEN}✓ Blob listing successful - found uploaded blob${NC}"
            BLOBS_LISTED=true
        elif echo "$BLOBS_LIST_RESPONSE" | grep -q -E '"blobs":\s*\[\s*\]|"blobs":\s*null'; then
            echo -e "${YELLOW}⚠ Blob listing returned empty - no blobs found${NC}"
            BLOBS_LISTED=false
        else
            echo -e "${RED}✗ Blob listing failed or returned invalid response${NC}"
            BLOBS_LISTED=false
        fi
    else
        echo -e "${YELLOW}⚠ Skipping blob listing - record creation failed${NC}"
        BLOBS_LISTED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test 11: Retrieve blob data
    echo -e "\n${YELLOW}=== Test 11: Retrieve Blob Data ===${NC}"
    if [ "$BLOB_UPLOADED" = true ]; then
        # Download the blob data
        TEMP_DOWNLOAD_FILE="/tmp/downloaded_blob_${BLOB_RECORD_KEY}.dat"
        BLOB_DOWNLOAD_ENDPOINT="${ENDPOINT}/api/stores/${STORE_ID}/records/${BLOB_RECORD_KEY}/blobs/${BLOB_NAME}"
        echo "Downloading from: $BLOB_DOWNLOAD_ENDPOINT"
        
        HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$TEMP_DOWNLOAD_FILE" "$BLOB_DOWNLOAD_ENDPOINT")
        
        if [ "$HTTP_STATUS" = "200" ]; then
            # Compare the downloaded data with original
            DOWNLOADED_DATA=$(cat "$TEMP_DOWNLOAD_FILE")
            if [ "$DOWNLOADED_DATA" = "$BLOB_DATA" ]; then
                echo -e "${GREEN}✓ Blob data retrieval successful - data matches original${NC}"
                echo "Original size: ${#BLOB_DATA} bytes, Downloaded size: ${#DOWNLOADED_DATA} bytes"
                BLOB_RETRIEVED=true
            else
                echo -e "${RED}✗ Blob data retrieval failed - data mismatch${NC}"
                echo "Original size: ${#BLOB_DATA} bytes, Downloaded size: ${#DOWNLOADED_DATA} bytes"
                echo "Original: $BLOB_DATA"
                echo "Downloaded: $DOWNLOADED_DATA"
                BLOB_RETRIEVED=false
            fi
        else
            echo -e "${RED}✗ Blob data retrieval failed - HTTP status: $HTTP_STATUS${NC}"
            BLOB_RETRIEVED=false
        fi
        
        # Clean up temp file
        rm -f "$TEMP_DOWNLOAD_FILE"
    else
        echo -e "${YELLOW}⚠ Skipping blob retrieval - upload failed${NC}"
        BLOB_RETRIEVED=false
    fi
    
    echo -e "${BLUE}Waiting 3 seconds...${NC}"
    sleep 3
    
    # Test Summary
    echo -e "\n${BLUE}===========================================${NC}"
    echo -e "${BLUE}API Test Summary${NC}"
    echo -e "${BLUE}===========================================${NC}"
    
    TOTAL_TESTS=13
    PASSED_TESTS=0
    
    # Count successful tests
    [ "$STORE_CREATED" = true ] && ((PASSED_TESTS++))
    [ "$STORES_FOUND" = true ] && ((PASSED_TESTS++))
    [ "$STORE_RETRIEVED" = true ] && ((PASSED_TESTS++))
    [ "$RECORD_CREATED" = true ] && ((PASSED_TESTS++))
    [ "$RECORDS_FOUND" = true ] && ((PASSED_TESTS++))
    [ "$RECORD_RETRIEVED" = true ] && ((PASSED_TESTS++))
    [ "$RECORD_UPDATED" = true ] && ((PASSED_TESTS++))
    [ "$RECORD_UPDATE_VERIFIED" = true ] && ((PASSED_TESTS++))
    [ "$BLOB_RECORD_CREATED" = true ] && ((PASSED_TESTS++))
    [ "$BLOB_UPLOADED" = true ] && ((PASSED_TESTS++))
    [ "$BLOBS_LISTED" = true ] && ((PASSED_TESTS++))
    [ "$BLOB_RETRIEVED" = true ] && ((PASSED_TESTS++))
    # Health check is always required to pass to get here
    ((PASSED_TESTS++))
    
    echo -e "Endpoint: ${ENDPOINT}"
    if [ -n "$ARCHITECTURE" ]; then
        echo -e "Architecture: ${ARCHITECTURE}"
    fi
    echo -e "Tests Passed: ${PASSED_TESTS}/${TOTAL_TESTS}"
    
    # Detailed test results
    echo -e "\nDetailed Results:"
    echo -e "  ✓ Health Check: Always passes to reach here"
    [ "$STORE_CREATED" = true ] && echo -e "  ✓ Store Creation" || echo -e "  ✗ Store Creation"
    [ "$STORES_FOUND" = true ] && echo -e "  ✓ Store Listing" || echo -e "  ✗ Store Listing"
    [ "$STORE_RETRIEVED" = true ] && echo -e "  ✓ Store Retrieval" || echo -e "  ✗ Store Retrieval"
    [ "$RECORD_CREATED" = true ] && echo -e "  ✓ Record Creation" || echo -e "  ✗ Record Creation"
    [ "$RECORDS_FOUND" = true ] && echo -e "  ✓ Record Listing" || echo -e "  ✗ Record Listing"
    [ "$RECORD_RETRIEVED" = true ] && echo -e "  ✓ Record Retrieval" || echo -e "  ✗ Record Retrieval"
    [ "$RECORD_UPDATED" = true ] && echo -e "  ✓ Record Update (PUT)" || echo -e "  ✗ Record Update (PUT)"
    [ "$RECORD_UPDATE_VERIFIED" = true ] && echo -e "  ✓ Record Update Verification" || echo -e "  ✗ Record Update Verification"
    [ "$BLOB_RECORD_CREATED" = true ] && echo -e "  ✓ Blob Record Creation" || echo -e "  ✗ Blob Record Creation"
    [ "$BLOB_UPLOADED" = true ] && echo -e "  ✓ Blob Data Upload" || echo -e "  ✗ Blob Data Upload"
    [ "$BLOBS_LISTED" = true ] && echo -e "  ✓ Blob Listing" || echo -e "  ✗ Blob Listing"
    [ "$BLOB_RETRIEVED" = true ] && echo -e "  ✓ Blob Data Retrieval" || echo -e "  ✗ Blob Data Retrieval"
    
    if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
        echo -e "\n${GREEN}🎉 All tests passed! API is working correctly with full blob support and PUT operations.${NC}"
        return 0
    elif [ $PASSED_TESTS -ge 10 ]; then
        echo -e "\n${YELLOW}⚠ Most tests passed, but some issues detected.${NC}"
        return 1
    else
        echo -e "\n${RED}❌ Multiple test failures detected. API may have issues.${NC}"
        return 2
    fi
}

# Main execution
main() {
    # Detect endpoint if not provided
    if [ -z "$OPEN_SAVES_ENDPOINT" ]; then
        if ! detect_endpoint; then
            exit 1
        fi
    else
        ENDPOINT="$OPEN_SAVES_ENDPOINT"
        echo -e "${GREEN}✓ Using provided endpoint: ${ENDPOINT}${NC}"
    fi
    
    # Run API tests
    test_api
    exit_code=$?
    
    echo -e "\n${BLUE}===========================================${NC}"
    echo -e "${BLUE}Test Complete${NC}"
    echo -e "${BLUE}===========================================${NC}"
    
    exit $exit_code
}

# Run main function
main "$@"
