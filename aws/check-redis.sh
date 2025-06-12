#!/bin/bash
# check-redis.sh - Script to check Redis cache entries for Open Saves

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Redis endpoint
REDIS_ENDPOINT="open-saves-cache.trfifg.0001.usw2.cache.amazonaws.com"

echo -e "${YELLOW}=== Redis Cache Check Tool ===${NC}"

# Create Redis test pod if it doesn't exist
if ! kubectl get pod -n open-saves redis-test &>/dev/null; then
  echo -e "${YELLOW}Creating Redis test pod...${NC}"
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
    command: ["sleep", "3600"]
  nodeSelector:
    kubernetes.io/arch: arm64
EOF

  echo -e "${YELLOW}Waiting for Redis test pod to be ready...${NC}"
  kubectl wait --for=condition=Ready pod/redis-test -n open-saves --timeout=60s
else
  echo -e "${GREEN}Redis test pod already exists.${NC}"
fi

# Test Redis connectivity
echo -e "\n${YELLOW}Testing Redis connectivity:${NC}"
REDIS_PING=$(kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT ping)
if [ "$REDIS_PING" == "PONG" ]; then
  echo -e "${GREEN}Redis connection successful: ${REDIS_PING}${NC}"
else
  echo -e "${RED}Redis connection failed${NC}"
  exit 1
fi

# Check for store cache keys
echo -e "\n${YELLOW}Checking for store cache keys:${NC}"
STORE_KEYS=$(kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT keys "store:*")
if [ -z "$STORE_KEYS" ]; then
  echo -e "${YELLOW}No store cache keys found.${NC}"
else
  echo -e "${GREEN}Found store cache keys:${NC}"
  echo "$STORE_KEYS"
  
  # Get content of first store cache key
  FIRST_STORE_KEY=$(echo "$STORE_KEYS" | head -1)
  echo -e "\n${YELLOW}Content of ${FIRST_STORE_KEY}:${NC}"
  kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT get "$FIRST_STORE_KEY"
fi

# Check for record cache keys
echo -e "\n${YELLOW}Checking for record cache keys:${NC}"
RECORD_KEYS=$(kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT keys "record:*")
if [ -z "$RECORD_KEYS" ]; then
  echo -e "${YELLOW}No record cache keys found.${NC}"
else
  echo -e "${GREEN}Found record cache keys:${NC}"
  echo "$RECORD_KEYS"
  
  # Get content of first record cache key
  FIRST_RECORD_KEY=$(echo "$RECORD_KEYS" | head -1)
  echo -e "\n${YELLOW}Content of ${FIRST_RECORD_KEY}:${NC}"
  kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT get "$FIRST_RECORD_KEY"
fi

# Check Redis statistics
echo -e "\n${YELLOW}Redis statistics:${NC}"
kubectl exec -n open-saves redis-test -- redis-cli -h $REDIS_ENDPOINT info | grep -E 'used_memory|connected_clients|keyspace'

echo -e "\n${GREEN}=== Redis Cache Check Complete ===${NC}"
