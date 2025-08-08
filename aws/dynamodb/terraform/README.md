# Open Saves AWS - Independent Terraform Deployment Steps

This directory contains completely independent Terraform configurations for deploying Open Saves on AWS. Each step is self-contained and uses AWS Systems Manager Parameter Store to share data between steps, eliminating the need for a top-level Terraform orchestration.

## Architecture Overview

The deployment is split into 5 independent steps:

1. **Step 1**: EKS Cluster and ECR Repository (Base Infrastructure)
2. **Step 2**: Data Infrastructure (DynamoDB, S3, ElastiCache)
3. **Step 3**: Container Images (Build and Push)
4. **Step 4**: Compute and Application (Node Groups, Kubernetes Resources)
5. **Step 5**: CloudFront and WAF (Security and Performance)

## Key Features

- **Complete Independence**: Each step has its own Terraform state and can be deployed/destroyed independently
- **Parameter Store Integration**: Steps communicate via AWS SSM Parameter Store instead of Terraform outputs
- **Architecture Support**: Full support for both AMD64 and ARM64 architectures
- **Security Best Practices**: Implements principle of least privilege with detailed IAM policies
- **Comprehensive Monitoring**: Includes CloudWatch dashboards and WAF logging
- **Easy Teardown**: Proper reverse-order teardown with dependency handling

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Docker (for container image building)
- Go >= 1.19 (for application building)
- kubectl (for Kubernetes management)

## Quick Start

### Full Deployment (AMD64)

```bash
# Deploy all steps for AMD64 architecture
./deploy-step1.sh
./deploy-step2.sh --architecture amd64
./deploy-step3.sh --architecture amd64
./deploy-step4.sh --architecture amd64
./deploy-step5.sh --architecture amd64
```

### Full Deployment (ARM64)

```bash
# Deploy all steps for ARM64 architecture
./deploy-step1.sh
./deploy-step2.sh --architecture arm64
./deploy-step3.sh --architecture arm64
./deploy-step4.sh --architecture arm64
./deploy-step5.sh --architecture arm64
```

### Architecture Switching

You can switch between architectures by tearing down steps 4-5 and redeploying with a different architecture:

```bash
# Switch from AMD64 to ARM64
./teardown-step5.sh --architecture amd64
./teardown-step4.sh --architecture amd64
./teardown-step3.sh --architecture amd64

./deploy-step3.sh --architecture arm64
./deploy-step4.sh --architecture arm64
./deploy-step5.sh --architecture arm64
```

## Detailed Step Information

### Step 1: EKS Cluster and ECR Repository

**Purpose**: Creates the foundational infrastructure including VPC, EKS cluster, and ECR repository.

**Resources Created**:
- VPC with public and private subnets across 3 AZs
- EKS cluster with OIDC provider
- ECR repository for container images
- IAM roles and policies for EKS cluster
- Internet Gateway, NAT Gateway, Route Tables

**Usage**:
```bash
./deploy-step1.sh [OPTIONS]

Options:
  --region REGION              AWS region (default: us-east-1)
  --cluster-name NAME          EKS cluster name (default: open-saves-cluster)
  --ecr-repo-name NAME         ECR repository name (default: open-saves)
  --environment ENV            Environment name (default: dev)
```

**Outputs Stored in SSM**:
- `/open-saves/step1/vpc_id`
- `/open-saves/step1/private_subnet_ids`
- `/open-saves/step1/ecr_repo_uri`
- `/open-saves/step1/cluster_endpoint`
- And more...

### Step 2: Data Infrastructure

**Purpose**: Creates all data storage and caching infrastructure.

**Resources Created**:
- DynamoDB tables (stores, records, metadata) with GSIs
- S3 bucket with security configurations
- ElastiCache Redis cluster
- Security groups and subnet groups
- SSM Parameter Store configuration

**Usage**:
```bash
./deploy-step2.sh [OPTIONS]

Options:
  --region REGION              AWS region (default: us-east-1)
  --architecture ARCH          Architecture for ElastiCache (amd64|arm64, default: amd64)
  --environment ENV            Environment name (default: dev)
```

**Architecture Impact**: The architecture parameter determines the ElastiCache node type:
- `amd64`: Uses `cache.t3.small`
- `arm64`: Uses `cache.t4g.small`

### Step 3: Container Images

**Purpose**: Builds and pushes container images to ECR.

**Resources Created**:
- Compiled Go application binaries
- Docker container images
- Images pushed to ECR with architecture-specific tags

**Usage**:
```bash
./deploy-step3.sh [OPTIONS]

Options:
  --region REGION              AWS region (default: us-east-1)
  --architecture ARCH          Architecture to build (amd64|arm64|both, default: amd64)
  --source-path PATH           Path to source code (default: /home/ec2-user/projects/open-saves-aws/aws)
  --environment ENV            Environment name (default: dev)
```

**Build Process**:
1. Compiles Go application for target architecture
2. Creates Docker image using appropriate Dockerfile
3. Pushes image to ECR with architecture tag
4. Updates configuration files

### Step 4: Compute and Application

**Purpose**: Deploys EKS node groups and the Open Saves application.

**Resources Created**:
- EKS node group with architecture-specific instances
- Kubernetes namespace, service account, and RBAC
- Application deployment with 2 replicas
- Load balancer service
- IAM roles with least-privilege policies

**Usage**:
```bash
./deploy-step4.sh [OPTIONS]

Options:
  --region REGION              AWS region (default: us-east-1)
  --architecture ARCH          Architecture for compute nodes (amd64|arm64, default: amd64)
  --namespace NAMESPACE        Kubernetes namespace (default: open-saves)
  --environment ENV            Environment name (default: dev)
```

**Instance Types by Architecture**:
- `amd64`: `t3.medium`, `t3.large`
- `arm64`: `t4g.medium`, `t4g.large`

**Security Features**:
- Principle of least privilege IAM policies
- Separate policies for DynamoDB, S3, and SSM access
- Explicit GSI permissions for query operations
- S3 bucket policy restricting access to service account role

### Step 5: CloudFront and WAF

**Purpose**: Adds CloudFront CDN and WAF for enhanced security and performance.

**Resources Created**:
- CloudFront distribution with custom origin
- WAF Web ACLs (regional and CloudFront)
- Security groups for CloudFront IP ranges
- CloudWatch dashboard for monitoring
- Rate limiting and SQL injection protection

**Usage**:
```bash
./deploy-step5.sh [OPTIONS]

Options:
  --region REGION              AWS region (default: us-east-1)
  --architecture ARCH          Architecture identifier (amd64|arm64, default: amd64)
  --environment ENV            Environment name (default: dev)
```

**Security Features**:
- DDoS protection via AWS Shield
- Rate limiting (10,000 req/sec for load testing)
- SQL injection protection
- Geographic restrictions (configurable)
- Origin verification headers

## Teardown Process

**Important**: Always teardown in reverse order (Step 5 → Step 4 → Step 3 → Step 2 → Step 1) to respect dependencies.

### Complete Teardown

```bash
# Teardown in reverse order
./teardown-step5.sh --architecture amd64
./teardown-step4.sh --architecture amd64
./teardown-step3.sh --architecture amd64 --delete-images
./teardown-step2.sh --empty-s3
./teardown-step1.sh --delete-ecr-images
```

### Teardown Options

Each teardown script supports cleanup options:

- **Step 5**: No special options
- **Step 4**: No special options
- **Step 3**: `--delete-images` to remove container images from ECR
- **Step 2**: `--empty-s3` to empty S3 bucket before destruction
- **Step 1**: `--delete-ecr-images` to remove all ECR images before destroying repository

## Parameter Store Structure

All inter-step communication happens via AWS SSM Parameter Store under the `/open-saves/` prefix:

```
/open-saves/
├── step1/
│   ├── vpc_id
│   ├── private_subnet_ids
│   ├── ecr_repo_uri
│   ├── cluster_endpoint
│   └── ...
├── step2/
│   ├── dynamodb_table_arns
│   ├── s3_bucket_name
│   ├── redis_endpoint
│   └── ...
├── step3/
│   ├── container_image_uri_amd64
│   ├── container_image_uri_arm64
│   └── ...
├── step4/
│   ├── load_balancer_hostname_amd64
│   ├── service_account_role_arn_amd64
│   └── ...
└── step5/
    ├── cloudfront_domain_name_amd64
    ├── waf_web_acl_arn_amd64
    └── ...
```

## Monitoring and Observability

### CloudWatch Dashboards

- **OpenSaves-Security-{architecture}**: WAF metrics, CloudFront requests, error rates

### Log Groups

- `/aws/waf/open-saves-{architecture}`: WAF logs
- EKS cluster logs (if enabled)

### Key Metrics to Monitor

- WAF blocked/counted requests
- CloudFront request volume and error rates
- EKS node and pod health
- DynamoDB throttling and errors
- S3 request metrics
- ElastiCache performance

## Troubleshooting

### Common Issues

1. **Parameter Not Found**: Ensure previous steps completed successfully
2. **ECR Push Failures**: Check AWS CLI credentials and ECR permissions
3. **Load Balancer Not Ready**: Wait 5-10 minutes for EKS load balancer provisioning
4. **CloudFront Deployment**: Can take 15-20 minutes to deploy globally

### Verification Commands

```bash
# Check parameter store values
aws ssm get-parameters-by-path --path "/open-saves/" --recursive

# Check EKS cluster status
aws eks describe-cluster --name open-saves-cluster

# Check Kubernetes resources
kubectl get all -n open-saves

# Test API endpoints
curl http://<load-balancer-hostname>:8080/health
```

### Cleanup Stuck Resources

If teardown fails due to stuck resources:

```bash
# Force cleanup VPC dependencies
./cleanup-vpc.sh

# Manually delete stuck load balancers
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `open-saves`)].LoadBalancerArn' --output text | xargs -I {} aws elbv2 delete-load-balancer --load-balancer-arn {}
```

## Security Considerations

### IAM Policies

All IAM policies follow the principle of least privilege:

- **DynamoDB**: Specific table and GSI access only
- **S3**: Bucket and object-level permissions for blob operations
- **SSM**: Read-only access to Open Saves parameters only

### Network Security

- Private subnets for all compute resources
- Security groups with minimal required access
- CloudFront origin verification headers
- WAF protection against common attacks

### Data Protection

- S3 server-side encryption (AES256)
- S3 versioning enabled
- S3 public access blocked
- DynamoDB encryption at rest (default)

## Cost Optimization

### Resource Sizing

- **EKS Nodes**: t3.medium/t4g.medium for development
- **ElastiCache**: t3.small/t4g.small for development
- **CloudFront**: PriceClass_100 (North America and Europe only)

### Cost Monitoring

Monitor costs for:
- EKS cluster and node groups
- ElastiCache Redis
- CloudFront data transfer
- DynamoDB read/write capacity
- S3 storage and requests

## Contributing

When modifying these Terraform configurations:

1. Maintain independence between steps
2. Use SSM Parameter Store for inter-step communication
3. Follow the established naming conventions
4. Update both deployment and teardown scripts
5. Test both AMD64 and ARM64 architectures
6. Update this README with any changes

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review AWS CloudWatch logs and metrics
3. Verify all prerequisites are met
4. Ensure proper step execution order
