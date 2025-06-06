#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Deployment Script ===${NC}"
echo -e "${YELLOW}This script will build and deploy Open Saves for AWS${NC}"

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
CLUSTER_NAME="open-saves-cluster"
NAMESPACE="open-saves"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"
REDIS_CLUSTER="open-saves-cache"
ECR_REPO_URI=""
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check for required tools
echo -e "${YELLOW}Checking for required tools...${NC}"
for tool in aws kubectl docker go; do
  if ! command -v $tool &> /dev/null; then
    echo -e "${RED}Error: $tool is not installed. Please install it before continuing.${NC}"
    exit 1
  fi
done
echo -e "${GREEN}All required tools are installed.${NC}"

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
  echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
  exit 1
fi
echo -e "${GREEN}AWS credentials verified.${NC}"

# Function to create DynamoDB tables
create_dynamodb_tables() {
  echo -e "${YELLOW}Creating DynamoDB tables...${NC}"
  
  # Create stores table
  if ! aws dynamodb describe-table --table-name open-saves-stores --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating stores table...${NC}"
    aws dynamodb create-table \
      --table-name open-saves-stores \
      --attribute-definitions AttributeName=store_id,AttributeType=S \
      --key-schema AttributeName=store_id,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region $AWS_REGION
    
    echo -e "${YELLOW}Waiting for stores table to be created...${NC}"
    aws dynamodb wait table-exists --table-name open-saves-stores --region $AWS_REGION
    echo -e "${GREEN}Stores table created.${NC}"
  else
    echo -e "${GREEN}Stores table already exists.${NC}"
  fi

  # Create records table
  if ! aws dynamodb describe-table --table-name open-saves-records --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating records table...${NC}"
    aws dynamodb create-table \
      --table-name open-saves-records \
      --attribute-definitions \
        AttributeName=store_id,AttributeType=S \
        AttributeName=record_id,AttributeType=S \
      --key-schema \
        AttributeName=store_id,KeyType=HASH \
        AttributeName=record_id,KeyType=RANGE \
      --billing-mode PAY_PER_REQUEST \
      --region $AWS_REGION
    
    echo -e "${YELLOW}Waiting for records table to be created...${NC}"
    aws dynamodb wait table-exists --table-name open-saves-records --region $AWS_REGION
    echo -e "${GREEN}Records table created.${NC}"
  else
    echo -e "${GREEN}Records table already exists.${NC}"
  fi

  # Create metadata table
  if ! aws dynamodb describe-table --table-name open-saves-metadata --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating metadata table...${NC}"
    aws dynamodb create-table \
      --table-name open-saves-metadata \
      --attribute-definitions \
        AttributeName=metadata_type,AttributeType=S \
        AttributeName=metadata_id,AttributeType=S \
      --key-schema \
        AttributeName=metadata_type,KeyType=HASH \
        AttributeName=metadata_id,KeyType=RANGE \
      --billing-mode PAY_PER_REQUEST \
      --region $AWS_REGION
    
    echo -e "${YELLOW}Waiting for metadata table to be created...${NC}"
    aws dynamodb wait table-exists --table-name open-saves-metadata --region $AWS_REGION
    echo -e "${GREEN}Metadata table created.${NC}"
  else
    echo -e "${GREEN}Metadata table already exists.${NC}"
  fi
}

# Function to create S3 bucket
create_s3_bucket() {
  echo -e "${YELLOW}Creating S3 bucket...${NC}"
  if ! aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
    aws s3api create-bucket \
      --bucket $S3_BUCKET \
      --region $AWS_REGION \
      --create-bucket-configuration LocationConstraint=$AWS_REGION
    
    echo -e "${GREEN}S3 bucket created.${NC}"
  else
    echo -e "${GREEN}S3 bucket already exists.${NC}"
  fi
}

# Function to create Redis cluster
create_redis_cluster() {
  echo -e "${YELLOW}Creating ElastiCache Redis cluster...${NC}"
  
  # Get VPC ID from EKS cluster
  VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || echo "")
  
  if [ -z "$VPC_ID" ]; then
    echo -e "${YELLOW}EKS cluster not found. Skipping Redis creation.${NC}"
    return
  fi
  
  echo -e "${YELLOW}Using VPC ID: ${VPC_ID} for Redis${NC}"

  # Get subnet IDs from the EKS VPC
  SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
  SUBNET_ARRAY=($SUBNET_IDS)

  # Create a new security group for Redis
  echo -e "${YELLOW}Creating security group for Redis in the EKS VPC...${NC}"
  REDIS_SG_ID=$(aws ec2 create-security-group --group-name open-saves-redis-sg-$(date +%s) --description "Security group for Open Saves Redis" --vpc-id $VPC_ID --query 'GroupId' --output text --region $AWS_REGION)
  echo -e "${GREEN}Created Redis security group: ${REDIS_SG_ID}${NC}"

  # Add ingress rule for Redis port
  aws ec2 authorize-security-group-ingress --group-id $REDIS_SG_ID --protocol tcp --port 6379 --cidr 0.0.0.0/0 --region $AWS_REGION
  echo -e "${GREEN}Added ingress rule to security group${NC}"

  # Create subnet group if it doesn't exist
  if ! aws elasticache describe-cache-subnet-groups --cache-subnet-group-name open-saves-cache-subnet --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating ElastiCache subnet group in the EKS VPC...${NC}"
    aws elasticache create-cache-subnet-group \
      --cache-subnet-group-name open-saves-cache-subnet \
      --cache-subnet-group-description "Subnet group for Open Saves Redis" \
      --subnet-ids ${SUBNET_ARRAY[@]} \
      --region $AWS_REGION
  else
    echo -e "${GREEN}ElastiCache subnet group already exists.${NC}"
  fi

  # Create Redis cluster if it doesn't exist
  if ! aws elasticache describe-cache-clusters --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating ElastiCache Redis cluster in the EKS VPC...${NC}"
    aws elasticache create-cache-cluster \
      --cache-cluster-id $REDIS_CLUSTER \
      --engine redis \
      --cache-node-type cache.t3.small \
      --num-cache-nodes 1 \
      --cache-subnet-group-name open-saves-cache-subnet \
      --security-group-ids $REDIS_SG_ID \
      --region $AWS_REGION

    echo -e "${YELLOW}Waiting for Redis cluster to be created (this will take 5-10 minutes)...${NC}"
    aws elasticache wait cache-cluster-available --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
  else
    echo -e "${GREEN}ElastiCache Redis cluster already exists.${NC}"
  fi

  # Get Redis endpoint
  REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id $REDIS_CLUSTER \
    --show-cache-node-info \
    --region $AWS_REGION \
    --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' \
    --output text)

  echo -e "${GREEN}Redis endpoint: ${REDIS_ENDPOINT}${NC}"
  
  # Update config with Redis endpoint
  if [ -f "config/config.yaml" ]; then
    sed -i "s/address:.*/address: \"${REDIS_ENDPOINT}:6379\"/" config/config.yaml
    echo -e "${GREEN}Updated config.yaml with Redis endpoint${NC}"
  fi
}

# Function to create EKS cluster
create_eks_cluster() {
  echo -e "${YELLOW}Checking if EKS cluster exists...${NC}"
  if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating EKS cluster (this will take 15-20 minutes)...${NC}"
    
    # Check if eksctl is available
    if command -v eksctl &> /dev/null; then
      echo -e "${YELLOW}Creating EKS cluster using eksctl...${NC}"
      eksctl create cluster \
        --name $CLUSTER_NAME \
        --region $AWS_REGION \
        --nodegroup-name standard-nodes \
        --node-type t3.medium \
        --nodes 2 \
        --nodes-min 1 \
        --nodes-max 4 \
        --managed
    else
      echo -e "${RED}eksctl not found. Please install eksctl or create the EKS cluster manually.${NC}"
      exit 1
    fi
    
    echo -e "${GREEN}EKS cluster created successfully.${NC}"
  else
    echo -e "${GREEN}EKS cluster already exists.${NC}"
  fi
  
  # Update kubeconfig
  echo -e "${YELLOW}Updating kubeconfig...${NC}"
  aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
  echo -e "${GREEN}Kubeconfig updated.${NC}"
  
  # Create IAM OIDC provider for EKS
  echo -e "${YELLOW}Creating IAM OIDC provider for EKS...${NC}"
  eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve --region $AWS_REGION
  echo -e "${GREEN}IAM OIDC provider created.${NC}"
}

# Function to build and push Docker image
build_and_push_image() {
  local arch=$1
  
  # Step 1: Build the application
  echo -e "${YELLOW}Building Open Saves AWS adapter for ${arch}...${NC}"
  cd "$(dirname "$0")"
  go mod tidy
  
  if [ "$arch" == "arm64" ]; then
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o open-saves-aws .
    DOCKERFILE="Dockerfile.arm64"
  else
    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .
    DOCKERFILE="Dockerfile.amd64.fixed"
  fi
  
  echo -e "${GREEN}Application built successfully.${NC}"

  # Step 2: Build Docker image
  echo -e "${YELLOW}Building Docker image for ${arch}...${NC}"
  docker build -f $DOCKERFILE -t $ECR_REPO_NAME:$arch .
  echo -e "${GREEN}Docker image built successfully.${NC}"

  # Step 3: Create ECR repository if it doesn't exist
  echo -e "${YELLOW}Setting up ECR repository...${NC}"
  if ! aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION &> /dev/null; then
    aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
    echo -e "${GREEN}ECR repository created.${NC}"
  else
    echo -e "${GREEN}ECR repository already exists.${NC}"
  fi

  # Get ECR repository URI
  ECR_REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION)
  echo -e "${GREEN}ECR repository URI: ${ECR_REPO_URI}${NC}"

  # Step 4: Push Docker image to ECR
  echo -e "${YELLOW}Pushing Docker image to ECR...${NC}"
  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
  docker tag $ECR_REPO_NAME:$arch $ECR_REPO_URI:$arch
  
  # If this is the default architecture, also tag as latest
  if [ "$arch" == "amd64" ]; then
    docker tag $ECR_REPO_NAME:$arch $ECR_REPO_URI:latest
    docker push $ECR_REPO_URI:latest
  fi
  
  docker push $ECR_REPO_URI:$arch
  echo -e "${GREEN}Docker image pushed to ECR.${NC}"
}

# Function to update EKS deployment
update_eks_deployment() {
  local arch=$1
  
  echo -e "${YELLOW}Updating EKS deployment for ${arch}...${NC}"
  
  # Check if namespace exists, create if it doesn't
  if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    kubectl create namespace $NAMESPACE
    echo -e "${GREEN}Namespace $NAMESPACE created.${NC}"
  fi
  
  # Create ConfigMap for configuration
  echo -e "${YELLOW}Creating ConfigMap...${NC}"
  kubectl -n $NAMESPACE create configmap open-saves-config --from-file=config/config.yaml --dry-run=client -o yaml | kubectl apply -f -
  
  # Get ECR repository URI if not already set
  if [ -z "$ECR_REPO_URI" ]; then
    ECR_REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION 2>/dev/null || echo "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}")
  fi
  
  # Create deployment YAML
  echo -e "${YELLOW}Creating deployment YAML...${NC}"
  cat > /tmp/deployment-${arch}.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: open-saves
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: open-saves
  template:
    metadata:
      labels:
        app: open-saves
    spec:
      serviceAccountName: open-saves-sa
EOF

  # Add node selector if architecture is specified
  if [ "$arch" != "both" ]; then
    cat >> /tmp/deployment-${arch}.yaml << EOF
      nodeSelector:
        kubernetes.io/arch: $arch
EOF
  fi

  # Continue with the rest of the deployment YAML
  cat >> /tmp/deployment-${arch}.yaml << EOF
      containers:
      - name: open-saves
        image: ${ECR_REPO_URI}:${arch}
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8081
          name: grpc
        volumeMounts:
        - name: config-volume
          mountPath: /etc/open-saves
        env:
        - name: AWS_REGION
          value: "$AWS_REGION"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config-volume
        configMap:
          name: open-saves-config
---
apiVersion: v1
kind: Service
metadata:
  name: open-saves
  namespace: $NAMESPACE
spec:
  selector:
    app: open-saves
  ports:
  - port: 8080
    targetPort: http
    name: http
  - port: 8081
    targetPort: grpc
    name: grpc
  type: LoadBalancer
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: open-saves-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: open-saves
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

  # Create service account if it doesn't exist
  if ! kubectl -n $NAMESPACE get serviceaccount open-saves-sa &> /dev/null; then
    echo -e "${YELLOW}Creating service account...${NC}"
    kubectl -n $NAMESPACE create serviceaccount open-saves-sa
    
    # Create IAM role for service account if eksctl is available
    if command -v eksctl &> /dev/null; then
      echo -e "${YELLOW}Creating IAM role for service account...${NC}"
      eksctl create iamserviceaccount \
        --name open-saves-sa \
        --namespace $NAMESPACE \
        --cluster $CLUSTER_NAME \
        --attach-policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
        --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
        --approve \
        --region $AWS_REGION || true
    else
      echo -e "${YELLOW}eksctl not found. Skipping IAM role creation for service account.${NC}"
      echo -e "${YELLOW}Make sure the service account has the necessary permissions.${NC}"
    fi
  fi

  # Apply the deployment
  echo -e "${YELLOW}Applying deployment...${NC}"
  kubectl apply -f /tmp/deployment-${arch}.yaml
  
  # Wait for deployment to be ready
  echo -e "${YELLOW}Waiting for deployment to be ready...${NC}"
  kubectl -n $NAMESPACE rollout status deployment/open-saves --timeout=300s || true
  
  # Get service URL
  echo -e "${YELLOW}Getting service URL...${NC}"
  SERVICE_URL=$(kubectl -n $NAMESPACE get service open-saves -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  
  if [ -n "$SERVICE_URL" ]; then
    echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
    echo -e "${GREEN}HTTP endpoint: ${SERVICE_URL}:8080${NC}"
    echo -e "${GREEN}gRPC endpoint: ${SERVICE_URL}:8081${NC}"
  else
    echo -e "${YELLOW}Service URL not yet available. Run the following command to check:${NC}"
    echo -e "${YELLOW}kubectl -n $NAMESPACE get service open-saves${NC}"
  fi
}

# Main execution flow
echo -e "${YELLOW}Starting Open Saves AWS deployment...${NC}"

# Ask user what to deploy
echo -e "${YELLOW}What would you like to deploy?${NC}"
echo -e "1. Full deployment (DynamoDB, S3, Redis, EKS, Docker image)"
echo -e "2. Infrastructure only (DynamoDB, S3, Redis)"
echo -e "3. Build and push Docker image only"
echo -e "4. Update EKS deployment only"
echo -e "5. Create EKS cluster only"
read -p "Enter your choice (1-5): " choice

# Ask for architecture if needed
if [[ "$choice" == "1" || "$choice" == "3" || "$choice" == "4" ]]; then
  echo -e "${YELLOW}Which architecture would you like to use?${NC}"
  echo -e "1. AMD64 (x86_64)"
  echo -e "2. ARM64 (aarch64)"
  echo -e "3. Both (multi-architecture)"
  read -p "Enter your choice (1-3): " arch_choice
  
  case $arch_choice in
    1) ARCH="amd64" ;;
    2) ARCH="arm64" ;;
    3) ARCH="both" ;;
    *) 
      echo -e "${RED}Invalid choice. Defaulting to AMD64.${NC}"
      ARCH="amd64"
      ;;
  esac
fi

case $choice in
  1)
    create_dynamodb_tables
    create_s3_bucket
    create_eks_cluster
    create_redis_cluster
    
    if [ "$ARCH" == "both" ]; then
      build_and_push_image "amd64"
      build_and_push_image "arm64"
    else
      build_and_push_image "$ARCH"
    fi
    
    update_eks_deployment "$ARCH"
    echo -e "${GREEN}Full deployment completed successfully!${NC}"
    ;;
  2)
    create_dynamodb_tables
    create_s3_bucket
    create_redis_cluster
    echo -e "${GREEN}Infrastructure deployment completed successfully!${NC}"
    ;;
  3)
    if [ "$ARCH" == "both" ]; then
      build_and_push_image "amd64"
      build_and_push_image "arm64"
    else
      build_and_push_image "$ARCH"
    fi
    echo -e "${GREEN}Docker image built and pushed successfully!${NC}"
    ;;
  4)
    update_eks_deployment "$ARCH"
    echo -e "${GREEN}EKS deployment updated successfully!${NC}"
    ;;
  5)
    create_eks_cluster
    echo -e "${GREEN}EKS cluster created successfully!${NC}"
    ;;
  *)
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}=== Open Saves AWS Deployment Completed ===${NC}"
echo -e "${YELLOW}To test the deployment, run:${NC}"
echo -e "${YELLOW}./open-saves-test.sh http://SERVICE_URL:8080${NC}"
