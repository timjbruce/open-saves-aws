#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Open Saves AWS Complete Deployment Script ===${NC}"
echo -e "${YELLOW}This script will build and deploy Open Saves to AWS${NC}"

# Check for required tools
echo -e "${YELLOW}Checking for required tools...${NC}"
for tool in aws kubectl docker go eksctl; do
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

# Set variables
AWS_REGION="us-west-2"
ECR_REPO_NAME="open-saves"
CLUSTER_NAME="open-saves-cluster"
NAMESPACE="open-saves"
DYNAMODB_TABLE="open-saves-records"
S3_BUCKET="open-saves-blobs-$(aws sts get-caller-identity --query Account --output text)"
REDIS_CLUSTER="open-saves-cache"

# Step 1: Build the application
echo -e "${YELLOW}Step 1: Building Open Saves AWS adapter...${NC}"
cd "$(dirname "$0")"
go mod tidy
GOOS=linux GOARCH=amd64 go build -o open-saves-aws .
echo -e "${GREEN}Application built successfully.${NC}"

# Step 2: Build Docker image
echo -e "${YELLOW}Step 2: Building Docker image...${NC}"
docker build --platform linux/amd64 -t $ECR_REPO_NAME:latest .
echo -e "${GREEN}Docker image built successfully.${NC}"

# Step 3: Create ECR repository if it doesn't exist
echo -e "${YELLOW}Step 3: Creating ECR repository...${NC}"
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
echo -e "${YELLOW}Step 4: Pushing Docker image to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest
docker push $ECR_REPO_URI:latest
echo -e "${GREEN}Docker image pushed to ECR.${NC}"

# Step 5: Create DynamoDB tables if they don't exist
echo -e "${YELLOW}Step 5: Creating DynamoDB tables...${NC}"

# Create stores table
if ! aws dynamodb describe-table --table-name open-saves-stores --region $AWS_REGION &> /dev/null; then
  echo -e "${YELLOW}Creating stores table...${NC}"
  aws dynamodb create-table \
    --table-name open-saves-stores \
    --attribute-definitions \
      AttributeName=store_id,AttributeType=S \
    --key-schema \
      AttributeName=store_id,KeyType=HASH \
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

# Step 6: Create S3 bucket if it doesn't exist
echo -e "${YELLOW}Step 6: Creating S3 bucket...${NC}"
if ! aws s3api head-bucket --bucket $S3_BUCKET 2>/dev/null; then
  aws s3api create-bucket \
    --bucket $S3_BUCKET \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION
  
  echo -e "${GREEN}S3 bucket created.${NC}"
else
  echo -e "${GREEN}S3 bucket already exists.${NC}"
fi

# Step 7: Create EKS cluster if it doesn't exist
echo -e "${YELLOW}Step 7: Checking if EKS cluster exists...${NC}"
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
  echo -e "${YELLOW}Creating EKS cluster (this will take 15-20 minutes)...${NC}"
  
  # Create VPC for EKS
  echo -e "${YELLOW}Creating VPC for EKS...${NC}"
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text --region $AWS_REGION)
  aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=open-saves-vpc --region $AWS_REGION
  
  # Create subnets
  echo -e "${YELLOW}Creating subnets...${NC}"
  SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${AWS_REGION}a --query 'Subnet.SubnetId' --output text --region $AWS_REGION)
  SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${AWS_REGION}b --query 'Subnet.SubnetId' --output text --region $AWS_REGION)
  SUBNET3_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone ${AWS_REGION}c --query 'Subnet.SubnetId' --output text --region $AWS_REGION)
  
  aws ec2 create-tags --resources $SUBNET1_ID --tags Key=Name,Value=open-saves-subnet-1 --region $AWS_REGION
  aws ec2 create-tags --resources $SUBNET2_ID --tags Key=Name,Value=open-saves-subnet-2 --region $AWS_REGION
  aws ec2 create-tags --resources $SUBNET3_ID --tags Key=Name,Value=open-saves-subnet-3 --region $AWS_REGION
  
  # Enable auto-assign public IP for subnets
  aws ec2 modify-subnet-attribute --subnet-id $SUBNET1_ID --map-public-ip-on-launch --region $AWS_REGION
  aws ec2 modify-subnet-attribute --subnet-id $SUBNET2_ID --map-public-ip-on-launch --region $AWS_REGION
  aws ec2 modify-subnet-attribute --subnet-id $SUBNET3_ID --map-public-ip-on-launch --region $AWS_REGION
  
  # Create Internet Gateway
  echo -e "${YELLOW}Creating Internet Gateway...${NC}"
  IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $AWS_REGION)
  aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=open-saves-igw --region $AWS_REGION
  aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION
  
  # Create Route Table
  echo -e "${YELLOW}Creating Route Table...${NC}"
  RTB_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $AWS_REGION)
  aws ec2 create-tags --resources $RTB_ID --tags Key=Name,Value=open-saves-rtb --region $AWS_REGION
  aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $AWS_REGION
  
  # Associate Route Table with Subnets
  aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET1_ID --region $AWS_REGION
  aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET2_ID --region $AWS_REGION
  aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET3_ID --region $AWS_REGION
  
  # Create security group for EKS
  echo -e "${YELLOW}Creating security group for EKS...${NC}"
  SG_ID=$(aws ec2 create-security-group --group-name open-saves-eks-sg --description "Security group for Open Saves EKS cluster" --vpc-id $VPC_ID --query 'GroupId' --output text --region $AWS_REGION)
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $AWS_REGION
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0 --region $AWS_REGION
  aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 8081 --cidr 0.0.0.0/0 --region $AWS_REGION
  
  # Create EKS Cluster Role
  echo -e "${YELLOW}Creating EKS Cluster Role...${NC}"
  aws iam create-role \
    --role-name open-saves-eks-cluster-role \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-cluster-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
    --region $AWS_REGION
  
  # Create EKS Node Role
  echo -e "${YELLOW}Creating EKS Node Role...${NC}"
  aws iam create-role \
    --role-name open-saves-eks-node-role \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-node-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-node-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-node-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-node-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
    --region $AWS_REGION
  
  aws iam attach-role-policy \
    --role-name open-saves-eks-node-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --region $AWS_REGION
  
  # Create EKS Cluster
  echo -e "${YELLOW}Creating EKS Cluster...${NC}"
  CLUSTER_ROLE_ARN=$(aws iam get-role --role-name open-saves-eks-cluster-role --query 'Role.Arn' --output text --region $AWS_REGION)
  
  aws eks create-cluster \
    --name $CLUSTER_NAME \
    --role-arn $CLUSTER_ROLE_ARN \
    --resources-vpc-config subnetIds=$SUBNET1_ID,$SUBNET2_ID,$SUBNET3_ID,securityGroupIds=$SG_ID \
    --region $AWS_REGION
  
  echo -e "${YELLOW}Waiting for EKS cluster to be created (this will take 10-15 minutes)...${NC}"
  aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
  
  # Create Node Group
  echo -e "${YELLOW}Creating EKS Node Group...${NC}"
  NODE_ROLE_ARN=$(aws iam get-role --role-name open-saves-eks-node-role --query 'Role.Arn' --output text --region $AWS_REGION)
  
  aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name open-saves-nodes \
    --node-role $NODE_ROLE_ARN \
    --subnets $SUBNET1_ID $SUBNET2_ID $SUBNET3_ID \
    --instance-types t3.medium \
    --scaling-config minSize=2,maxSize=4,desiredSize=2 \
    --region $AWS_REGION
  
  echo -e "${YELLOW}Waiting for EKS node group to be created (this will take 5-10 minutes)...${NC}"
  aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name open-saves-nodes --region $AWS_REGION
  
  echo -e "${GREEN}EKS cluster created successfully.${NC}"
  
  # Store the VPC ID for later use
  echo $VPC_ID > .vpc_id
else
  echo -e "${GREEN}EKS cluster already exists.${NC}"
  
  # Get the VPC ID from the EKS cluster
  VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
  echo $VPC_ID > .vpc_id
fi

# Step 8: Create ElastiCache Redis cluster in the SAME VPC as EKS
echo -e "${YELLOW}Step 8: Creating ElastiCache Redis cluster in the EKS VPC...${NC}"

# Get VPC ID (from file or EKS cluster)
if [ -f .vpc_id ]; then
  VPC_ID=$(cat .vpc_id)
else
  VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
fi

echo -e "${YELLOW}Using VPC ID: ${VPC_ID} for both EKS and ElastiCache${NC}"

# Get subnet IDs from the EKS VPC
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION)
SUBNET_ARRAY=($SUBNET_IDS)

# Create a new security group for Redis with timestamp to ensure uniqueness
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
  echo -e "${GREEN}Using security group ID: ${REDIS_SG_ID}${NC}"
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

# Step 9: Update kubeconfig
echo -e "${YELLOW}Step 9: Updating kubeconfig...${NC}"
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
echo -e "${GREEN}Kubeconfig updated.${NC}"

# Step 10: Create IAM OIDC provider for EKS
echo -e "${YELLOW}Step 10: Creating IAM OIDC provider for EKS...${NC}"
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve --region $AWS_REGION
echo -e "${GREEN}IAM OIDC provider created.${NC}"

# Step 11: Create IAM service account for Open Saves
echo -e "${YELLOW}Step 11: Creating IAM service account for Open Saves...${NC}"
eksctl create iamserviceaccount \
  --name open-saves-sa \
  --namespace $NAMESPACE \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
  --approve \
  --region $AWS_REGION
echo -e "${GREEN}IAM service account created.${NC}"

# Step 12: Update config.yaml with the correct values
echo -e "${YELLOW}Step 12: Updating configuration...${NC}"
mkdir -p config
cat > config/config.yaml << EOF
server:
  http_port: 8080
  grpc_port: 8081

aws:
  region: "$AWS_REGION"
  dynamodb:
    stores_table: "open-saves-stores"
    records_table: "open-saves-records"
    metadata_table: "open-saves-metadata"
  s3:
    bucket_name: "$S3_BUCKET"
  elasticache:
    address: "${REDIS_ENDPOINT}:6379"
    ttl: 3600
EOF
echo -e "${GREEN}Configuration updated.${NC}"

# Step 13: Create deployment YAML
echo -e "${YELLOW}Step 13: Creating deployment YAML...${NC}"
cat > deploy.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: open-saves-config
  namespace: $NAMESPACE
data:
  config.yaml: |
    server:
      http_port: 8080
      grpc_port: 8081
    aws:
      region: "$AWS_REGION"
      dynamodb:
        stores_table: "open-saves-stores"
        records_table: "open-saves-records"
        metadata_table: "open-saves-metadata"
      s3:
        bucket_name: "$S3_BUCKET"
      elasticache:
        address: "${REDIS_ENDPOINT}:6379"
        ttl: 3600
---
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
      containers:
      - name: open-saves
        image: $ECR_REPO_URI:latest
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8081
          name: grpc
        volumeMounts:
        - name: config-volume
          mountPath: /etc/open-saves
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
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
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: open-saves-lb
  namespace: $NAMESPACE
spec:
  selector:
    app: open-saves
  ports:
  - port: 80
    targetPort: http
    name: http
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
echo -e "${GREEN}Deployment YAML created.${NC}"

# Step 14: Deploy to Kubernetes
echo -e "${YELLOW}Step 14: Deploying to Kubernetes...${NC}"
kubectl apply -f deploy.yaml
echo -e "${GREEN}Deployment applied.${NC}"

# Step 15: Wait for deployment to be ready
echo -e "${YELLOW}Step 15: Waiting for deployment to be ready...${NC}"
kubectl -n $NAMESPACE rollout status deployment/open-saves --timeout=300s || true

# Step 16: Get service URL
echo -e "${YELLOW}Step 16: Getting service URL...${NC}"
echo -e "${YELLOW}Waiting for Load Balancer to be provisioned (this may take a few minutes)...${NC}"
sleep 60

SERVICE_URL=$(kubectl -n $NAMESPACE get service open-saves-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo -e "${GREEN}=== Deployment Complete! ===${NC}"
echo -e "${GREEN}Open Saves is now running on AWS with DynamoDB integration.${NC}"
echo -e "${GREEN}Service URL: http://${SERVICE_URL}${NC}"
echo -e "${GREEN}You can test the deployment with:${NC}"
echo -e "${GREEN}curl http://${SERVICE_URL}/health${NC}"
echo -e "${GREEN}curl http://${SERVICE_URL}/api/stores${NC}"
echo -e "${GREEN}To run the test client:${NC}"
echo -e "${GREEN}./open-saves-test.sh http://${SERVICE_URL}${NC}"
