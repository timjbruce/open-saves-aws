#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Step-by-Step Deployment Script ===${NC}"
echo -e "${YELLOW}This script allows deploying Open Saves for AWS in discrete steps${NC}"

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="dev-open-saves"  # Updated to match the actual repository name
CLUSTER_NAME="open-saves-cluster-new"
NAMESPACE="open-saves"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"
REDIS_CLUSTER="open-saves-cache"
ECR_REPO_URI=""
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Load environment variables if they exist
if [ -f .env.deploy ]; then
  source .env.deploy
  echo -e "${GREEN}Loaded environment variables from .env.deploy${NC}"
fi

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

# Function to create EKS cluster and ECR registry
create_eks_cluster_and_ecr() {
  echo -e "${YELLOW}Step 1: Creating EKS cluster and ECR registry${NC}"
  
  # Create ECR repository if it doesn't exist
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
  
  # Store ECR repository URI in a file for use between steps
  echo "ECR_REPO_URI=$ECR_REPO_URI" > .env.deploy
  echo -e "${GREEN}Stored ECR repository URI in .env.deploy file${NC}"
  
  # Create EKS cluster
  echo -e "${YELLOW}Checking if EKS cluster exists...${NC}"
  if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating EKS cluster (this will take 15-20 minutes)...${NC}"
    
    # Check if eksctl is available
    if command -v eksctl &> /dev/null; then
      echo -e "${YELLOW}Creating EKS cluster using eksctl...${NC}"
      eksctl create cluster \
        --name $CLUSTER_NAME \
        --region $AWS_REGION \
        --without-nodegroup
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
  
  echo -e "${GREEN}Step 1 completed successfully!${NC}"
}

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
    aws s3api create-bucket --bucket $S3_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
    echo -e "${GREEN}S3 bucket created.${NC}"
  else
    echo -e "${GREEN}S3 bucket already exists.${NC}"
  fi
}

# Function to create Redis cluster
create_redis_cluster() {
  local arch=$1
  echo -e "${YELLOW}Creating ElastiCache Redis cluster for ${arch} architecture...${NC}"
  
  # Get VPC ID from EKS cluster
  VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
  echo -e "${YELLOW}Using VPC ID: ${VPC_ID} for Redis${NC}"
  
  # Create security group for Redis
  SG_NAME="open-saves-redis-sg-$(date +%s)"
  SG_ID=$(aws ec2 create-security-group --group-name $SG_NAME --description "Security group for Open Saves Redis" --vpc-id $VPC_ID --region $AWS_REGION --query 'GroupId' --output text)
  echo -e "${GREEN}Created Redis security group: ${SG_ID}${NC}"
  
  # Add ingress rule to allow Redis port
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 6379 --cidr 0.0.0.0/0 --region $AWS_REGION
  echo -e "${GREEN}Added ingress rule to security group${NC}"
  
  # Get subnet IDs from EKS cluster
  SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text | tr '\t' ' ')
  
  # Create subnet group for Redis
  echo -e "${YELLOW}Creating ElastiCache subnet group in the EKS VPC...${NC}"
  aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name open-saves-cache-subnet \
    --cache-subnet-group-description "Subnet group for Open Saves Redis" \
    --subnet-ids $SUBNET_IDS \
    --region $AWS_REGION
  
  # Select Redis instance type based on architecture
  if [ "$arch" == "arm64" ]; then
    echo -e "${YELLOW}Using Graviton-based Redis instance type (cache.t4g.small) for arm64 architecture${NC}"
    REDIS_INSTANCE_TYPE="cache.t4g.small"
  else
    echo -e "${YELLOW}Using x86-based Redis instance type (cache.t3.small)${NC}"
    REDIS_INSTANCE_TYPE="cache.t3.small"
  fi
  
  # Create Redis cluster
  echo -e "${YELLOW}Creating ElastiCache Redis cluster in the EKS VPC...${NC}"
  aws elasticache create-cache-cluster \
    --cache-cluster-id $REDIS_CLUSTER \
    --engine redis \
    --cache-node-type $REDIS_INSTANCE_TYPE \
    --num-cache-nodes 1 \
    --cache-subnet-group-name open-saves-cache-subnet \
    --security-group-ids $SG_ID \
    --region $AWS_REGION
  
  echo -e "${YELLOW}Waiting for Redis cluster to be created (this will take 5-10 minutes)...${NC}"
  aws elasticache wait cache-cluster-available --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION
  
  # Get Redis endpoint
  REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters --cache-cluster-id $REDIS_CLUSTER --region $AWS_REGION --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)
  echo -e "${GREEN}Redis endpoint: ${REDIS_ENDPOINT}${NC}"
  
  # Update config.yaml with Redis endpoint
  sed -i "s/address: .*/address: \"${REDIS_ENDPOINT}:6379\"/" config/config.yaml
  echo -e "${GREEN}Updated config.yaml with Redis endpoint${NC}"
}

# Function to deploy infrastructure
deploy_infrastructure() {
  echo -e "${YELLOW}Step 2: Deploying infrastructure (DynamoDB, S3, Redis)${NC}"
  
  # Ask for architecture if not already set
  if [ -z "$ARCH" ]; then
    echo -e "${YELLOW}Which architecture would you like to use for Redis?${NC}"
    echo -e "1. AMD64 (x86_64)"
    echo -e "2. ARM64 (aarch64)"
    read -p "Enter your choice (1-2): " arch_choice
    
    case $arch_choice in
      1) ARCH="amd64" ;;
      2) ARCH="arm64" ;;
      *) 
        echo -e "${RED}Invalid choice. Defaulting to AMD64.${NC}"
        ARCH="amd64"
        ;;
    esac
  fi
  
  create_dynamodb_tables
  create_s3_bucket
  create_redis_cluster $ARCH
  
  echo -e "${GREEN}Step 2 completed successfully!${NC}"
}

# Function to build and push Docker image
build_and_push_image() {
  local arch=$1
  echo -e "${YELLOW}Step 3: Building and pushing Docker image for ${arch} architecture${NC}"
  
  # Load ECR repository URI from file
  if [ -f .env.deploy ]; then
    source .env.deploy
    echo -e "${GREEN}Loaded ECR repository URI: ${ECR_REPO_URI}${NC}"
  else
    # Fallback if file doesn't exist
    ECR_REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION)
    echo -e "${YELLOW}ECR repository URI not found in file, fetched from AWS: ${ECR_REPO_URI}${NC}"
  fi
  
  # Verify that the ECR repository URI is valid
  if [ -z "$ECR_REPO_URI" ]; then
    echo -e "${RED}Error: ECR repository URI is empty. Cannot continue with build and push.${NC}"
    exit 1
  fi
  
  # Step 1: Build the application
  echo -e "${YELLOW}Building Open Saves AWS adapter for ${arch}...${NC}"
  cd "$(dirname "$0")"
  go mod tidy
  
  if [ "$arch" == "arm64" ]; then
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o open-saves-aws .
    DOCKERFILE="Dockerfile.arm64"
  else
    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o open-saves-aws .
    DOCKERFILE="Dockerfile"
  fi
  
  echo -e "${GREEN}Application built successfully.${NC}"

  # Step 2: Build Docker image
  echo -e "${YELLOW}Building Docker image for ${arch}...${NC}"
  if [ "$arch" == "arm64" ]; then
    # Use ARM64 specific Dockerfile
    docker build -f $DOCKERFILE -t $ECR_REPO_NAME:$arch .
  else
    # Use AMD64 specific Dockerfile
    docker build -f $DOCKERFILE -t $ECR_REPO_NAME:$arch .
  fi
  echo -e "${GREEN}Docker image built successfully.${NC}"

  # Step 3: Push Docker image to ECR
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
  
  # Update config.yaml with ECR repository URI
  echo -e "${YELLOW}Updating config.yaml with ECR repository URI...${NC}"
  if grep -q "ecr:" config/config.yaml; then
    # Update existing entry
    sed -i "s|repository_uri: .*|repository_uri: \"$ECR_REPO_URI\"|" config/config.yaml
  else
    # Add new entry
    sed -i "/elasticache:/a\\  ecr:\\n    repository_uri: \"$ECR_REPO_URI\"" config/config.yaml
  fi
  echo -e "${GREEN}Updated config.yaml with ECR repository URI${NC}"
  
  echo -e "${GREEN}Step 3 completed successfully!${NC}"
}

# Function to deploy compute nodes and application
deploy_compute_and_app() {
  local arch=$1
  echo -e "${YELLOW}Step 4: Deploying compute nodes and application for ${arch} architecture${NC}"
  
  # Load ECR repository URI from file
  if [ -f .env.deploy ]; then
    source .env.deploy
    echo -e "${GREEN}Loaded ECR repository URI: ${ECR_REPO_URI}${NC}"
  else
    # Fallback if file doesn't exist
    ECR_REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION)
    echo -e "${YELLOW}ECR repository URI not found in file, fetched from AWS: ${ECR_REPO_URI}${NC}"
  fi
  
  # Verify that the ECR repository URI is valid
  if [ -z "$ECR_REPO_URI" ]; then
    echo -e "${RED}Error: ECR repository URI is empty. Cannot continue with deployment.${NC}"
    exit 1
  fi
  
  # Verify that the image exists in ECR
  echo -e "${YELLOW}Verifying image exists in ECR...${NC}"
  if ! aws ecr describe-images --repository-name $ECR_REPO_NAME --image-ids imageTag=$arch --region $AWS_REGION &> /dev/null; then
    echo -e "${RED}Error: Image with tag '${arch}' not found in ECR repository '${ECR_REPO_NAME}'.${NC}"
    echo -e "${RED}Please build and push the image first using Step 3.${NC}"
    exit 1
  fi
  echo -e "${GREEN}Image verification successful.${NC}"
  
  # Create node group for the specified architecture
  echo -e "${YELLOW}Creating node group for ${arch} architecture...${NC}"
  
  NODE_GROUP_NAME="${arch}-nodes"
  
  if [ "$arch" == "arm64" ]; then
    INSTANCE_TYPE="t4g.medium"
    AMI_TYPE="AL2_ARM_64"
  else
    INSTANCE_TYPE="t3.medium"
    AMI_TYPE="AL2_x86_64"
  fi
  
  # Check if node group exists
  if ! aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODE_GROUP_NAME --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}Creating ${arch} node group...${NC}"
    eksctl create nodegroup \
      --cluster $CLUSTER_NAME \
      --region $AWS_REGION \
      --name $NODE_GROUP_NAME \
      --node-type $INSTANCE_TYPE \
      --nodes 2 \
      --nodes-min 1 \
      --nodes-max 4 \
      --managed \
      --asg-access
    
    echo -e "${GREEN}Node group created.${NC}"
  else
    echo -e "${GREEN}Node group already exists.${NC}"
  fi
  
  # Deploy the application
  echo -e "${YELLOW}Deploying application...${NC}"
  
  # Check if namespace exists, create if it doesn't
  if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    kubectl create namespace $NAMESPACE
    echo -e "${GREEN}Namespace $NAMESPACE created.${NC}"
  fi
  
  # Create ConfigMap for configuration
  echo -e "${YELLOW}Creating ConfigMap...${NC}"
  kubectl create configmap open-saves-config --from-file=config.yaml=config/config.yaml -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  
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
      nodeSelector:
        kubernetes.io/arch: $arch
      containers:
      - name: open-saves
        image: ${ECR_REPO_URI}:${arch}
        command: ["/app/open-saves-aws"]
        args: ["--config", "/etc/open-saves/config.yaml"]
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
  - name: http
    port: 8080
    targetPort: 8080
  - name: grpc
    port: 8081
    targetPort: 8081
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
  echo -e "${YELLOW}Creating service account...${NC}"
  kubectl -n $NAMESPACE create serviceaccount open-saves-sa --dry-run=client -o yaml | kubectl apply -f -
  
  # Create IAM role for service account if eksctl is available
  echo -e "${YELLOW}Creating IAM role for service account...${NC}"
  eksctl create iamserviceaccount \
    --name open-saves-sa \
    --namespace $NAMESPACE \
    --cluster $CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --approve \
    --region $AWS_REGION || true
  
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
  
  echo -e "${GREEN}Step 4 completed successfully!${NC}"
}

# Function to run tests
run_tests() {
  echo -e "${YELLOW}Step 5: Running tests${NC}"
  
  # Get service URL
  SERVICE_URL=$(kubectl -n $NAMESPACE get service open-saves -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  
  if [ -n "$SERVICE_URL" ]; then
    echo -e "${YELLOW}Running tests against ${SERVICE_URL}:8080${NC}"
    ./open-saves-test.sh http://${SERVICE_URL}:8080
  else
    echo -e "${RED}Service URL not available. Cannot run tests.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Step 5 completed successfully!${NC}"
}

# Main menu
echo -e "${YELLOW}Starting Open Saves AWS deployment...${NC}"
echo -e "${YELLOW}Please select a step to execute:${NC}"
echo -e "1. Step 1: Create EKS cluster and ECR registry"
echo -e "2. Step 2: Deploy infrastructure (DynamoDB, S3, Redis)"
echo -e "3. Step 3: Build and push Docker image"
echo -e "4. Step 4: Deploy compute nodes and application"
echo -e "5. Step 5: Run tests"
echo -e "6. Execute all steps in sequence"
echo -e "7. Exit"

read -p "Enter your choice (1-7): " choice

# Ask for architecture if needed
if [[ $choice -eq 2 || $choice -eq 3 || $choice -eq 4 || $choice -eq 6 ]]; then
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
    create_eks_cluster_and_ecr
    ;;
  2)
    deploy_infrastructure
    ;;
  3)
    if [ "$ARCH" == "both" ]; then
      build_and_push_image "amd64"
      build_and_push_image "arm64"
    else
      build_and_push_image "$ARCH"
    fi
    ;;
  4)
    if [ "$ARCH" == "both" ]; then
      deploy_compute_and_app "amd64"
      deploy_compute_and_app "arm64"
    else
      deploy_compute_and_app "$ARCH"
    fi
    ;;
  5)
    run_tests
    ;;
  6)
    create_eks_cluster_and_ecr
    deploy_infrastructure
    if [ "$ARCH" == "both" ]; then
      build_and_push_image "amd64"
      build_and_push_image "arm64"
      deploy_compute_and_app "amd64"
      deploy_compute_and_app "arm64"
    else
      build_and_push_image "$ARCH"
      deploy_compute_and_app "$ARCH"
    fi
    run_tests
    ;;
  7)
    echo -e "${YELLOW}Exiting.${NC}"
    exit 0
    ;;
  *)
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}=== Open Saves AWS Deployment Step Completed ===${NC}"
