# Open Saves AWS Implementation

This is the AWS implementation of Open Saves, a cloud-based storage solution for game save data.

## Overview

Open Saves AWS uses the following AWS services:
- Amazon EKS for container orchestration
- Amazon DocumentDB for metadata and record storage
- Amazon S3 for blob storage
- Amazon ElastiCache Redis for caching
- Amazon CloudFront and WAF for security and performance

## Architecture

The Open Saves AWS implementation follows a completely independent step-based architecture:

1. **Step 1 - EKS Cluster and ECR**: VPC, subnets, EKS cluster, and ECR repository
2. **Step 2 - Data Infrastructure**: DocumentDB cluster with collections, S3 bucket, and ElastiCache Redis
3. **Step 3 - Container Images**: Build and push Open Saves container images
4. **Step 4 - Compute and Application**: EKS node groups, Kubernetes resources, and application deployment
5. **Step 5 - CloudFront and WAF**: CDN and security layer for production traffic

## Key Features

- **Complete Independence**: Each step has its own Terraform state and can be deployed/destroyed independently
- **Parameter Store Integration**: Steps communicate via AWS SSM Parameter Store instead of Terraform outputs
- **Architecture Support**: Full support for both AMD64 and ARM64 architectures with easy switching
- **Security Best Practices**: Implements principle of least privilege with detailed IAM policies
- **Production Ready**: CloudFront CDN, WAF protection, comprehensive monitoring
- **Easy Teardown**: Proper reverse-order teardown with dependency handling

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Docker (for container image building)
- Go >= 1.19 (for application building)
- kubectl (for Kubernetes management)

## Quick Start

### Option 1: Master Deployment Script (Recommended)

```bash
cd terraform

# Deploy everything for AMD64
./deploy-full.sh --architecture amd64

# Deploy everything for ARM64
./deploy-full.sh --architecture arm64

# Interactive deployment with confirmations
./deploy-full.sh --interactive --architecture amd64

# Deploy only specific steps
./deploy-full.sh --only-steps "3,4,5" --architecture arm64
```

### Option 2: Individual Step Deployment

```bash
cd terraform

# Deploy each step individually
./deploy-step1.sh
./deploy-step2.sh --architecture amd64
./deploy-step3.sh --architecture amd64
./deploy-step4.sh --architecture amd64
./deploy-step5.sh --architecture amd64
```

### Option 3: Architecture Switching

```bash
cd terraform

# Switch from current architecture to ARM64
./switch-architecture.sh --to-arch arm64

# Explicitly switch from AMD64 to ARM64
./switch-architecture.sh --from-arch amd64 --to-arch arm64
```

## Deployment Steps Detail

### Step 1: EKS Cluster and ECR Repository
- Creates VPC with public/private subnets across 3 AZs
- Deploys EKS cluster with OIDC provider
- Creates ECR repository for container images
- Sets up IAM roles and networking components

### Step 2: Data Infrastructure
- Creates DocumentDB cluster with three collections:
  - **stores**: Store metadata and configuration
  - **records**: Game save records and properties  
  - **metadata**: Additional metadata for stores and records
- Deploys S3 bucket with security configurations
- Sets up ElastiCache Redis cluster (architecture-specific)
- Configures security groups and parameter store

### Step 3: Container Images
- Builds Go application for target architecture
- Creates Docker images using appropriate Dockerfile
- Pushes images to ECR with architecture tags
- Updates configuration files

### Step 4: Compute and Application
- Deploys EKS node groups with architecture-specific instances
- Creates Kubernetes namespace, service account, and RBAC
- Deploys Open Saves application with 2 replicas
- Sets up load balancer service and IAM policies

### Step 5: CloudFront and WAF
- Creates CloudFront distribution with custom origin
- Deploys WAF Web ACLs for security
- Sets up CloudWatch dashboards for monitoring
- Configures rate limiting and attack protection

## Teardown

### Complete Teardown

```bash
cd terraform

# Master teardown script (recommended)
./teardown-full.sh --architecture amd64 --delete-images --empty-s3 --delete-ecr-images

# Or teardown individual steps in reverse order
./teardown-step5.sh --architecture amd64
./teardown-step4.sh --architecture amd64
./teardown-step3.sh --architecture amd64 --delete-images
./teardown-step2.sh --empty-s3
./teardown-step1.sh --delete-ecr-images
```

## Testing

After deployment, test the API using the provided test script:

```bash
# Test via load balancer (Step 4 complete)
./open-saves-test.sh http://<load-balancer-hostname>:8080

# Test via CloudFront (Step 5 complete)
./open-saves-test.sh https://<cloudfront-domain>
```

Get endpoints from SSM Parameter Store:
```bash
# Load balancer hostname
aws ssm get-parameter --name "/open-saves/step4/load_balancer_hostname_amd64" --query 'Parameter.Value' --output text

# CloudFront domain
aws ssm get-parameter --name "/open-saves/step5/cloudfront_domain_name_amd64" --query 'Parameter.Value' --output text
```

## Configuration

The deployment uses AWS Systems Manager Parameter Store for configuration management:

- **Step Communication**: All steps share data via `/open-saves/stepX/` parameters
- **Application Config**: Stored in `/etc/open-saves/config.yaml` parameter
- **Security**: No sensitive data in Terraform state files

## Architecture Support

### AMD64 Architecture
- Uses `t3.medium`/`t3.large` for EKS nodes
- Uses `cache.t3.small` for ElastiCache
- Standard x86_64 container images

### ARM64 Architecture  
- Uses `t4g.medium`/`t4g.large` for EKS nodes
- Uses `cache.t4g.small` for ElastiCache
- ARM64-optimized container images

### Switching Architectures
The system supports easy switching between architectures by tearing down and redeploying steps 3-5:

```bash
./switch-architecture.sh --to-arch arm64
```

## Monitoring and Observability

### CloudWatch Dashboards
- **OpenSaves-Security-{architecture}**: WAF metrics, CloudFront requests, error rates

### Key Metrics
- WAF blocked/counted requests
- CloudFront request volume and error rates
- EKS node and pod health
- DocumentDB connection and query performance
- S3 request metrics
- ElastiCache performance

### Log Groups
- `/aws/waf/open-saves-{architecture}`: WAF logs
- EKS cluster logs (if enabled)

## Security Features

### IAM Policies (Principle of Least Privilege)
- **DocumentDB**: Access to specific cluster and database only
- **S3**: Bucket and object-level permissions for blob operations
- **SSM**: Read-only access to Open Saves parameters only

### Network Security
- Private subnets for all compute resources
- Security groups with minimal required access
- CloudFront origin verification headers

### WAF Protection
- DDoS protection via AWS Shield
- Rate limiting (configurable)
- SQL injection protection
- Geographic restrictions (configurable)

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
If teardown fails due to stuck resources, you can use the cleanup utilities in the old terraform directory:

```bash
cd terraform-old-approach
./cleanup-vpc.sh
./force-cleanup-vpc.sh
```

## Directory Structure

```
aws/
├── terraform/                    # Independent Terraform steps
│   ├── step1-cluster-ecr/       # EKS cluster and ECR
│   ├── step2-infrastructure/    # DocumentDB, S3, ElastiCache
│   ├── step3-container-images/  # Container image builds
│   ├── step4-compute-app/       # EKS nodes and application
│   ├── step5-cloudfront-waf/    # CloudFront and WAF
│   ├── deploy-full.sh           # Master deployment script
│   ├── teardown-full.sh         # Master teardown script
│   ├── switch-architecture.sh   # Architecture switching
│   └── README.md                # Detailed deployment guide
├── terraform-old-approach/      # Archived old approach
├── open-saves-test.sh           # API testing script
└── README.md                    # This file
```

## Advanced Usage

### Selective Deployment
```bash
# Deploy only infrastructure steps
./deploy-full.sh --only-steps "1,2" --architecture amd64

# Skip CloudFront deployment
./deploy-full.sh --skip-steps "5" --architecture arm64
```

### Interactive Mode
```bash
# Prompt before each step
./deploy-full.sh --interactive --architecture amd64
```

### Custom Configuration
```bash
# Custom cluster name and region
./deploy-step1.sh --cluster-name my-cluster --region us-west-2

# Custom source path for container builds
./deploy-step3.sh --source-path /path/to/source --architecture arm64
```

## Cost Optimization

### Development Environment
- Use `t3.medium`/`t4g.medium` for EKS nodes
- Use `cache.t3.small`/`cache.t4g.small` for ElastiCache
- Deploy only necessary steps (skip Step 5 for development)

### Production Environment
- Scale up instance types as needed
- Enable CloudFront (Step 5) for global performance
- Monitor costs via AWS Cost Explorer

## Contributing

When modifying the deployment:

1. Maintain independence between steps
2. Use SSM Parameter Store for inter-step communication
3. Follow established naming conventions
4. Update both deployment and teardown scripts
5. Test both AMD64 and ARM64 architectures
6. Update documentation

## Support

For detailed deployment information, see the [Terraform README](terraform/README.md).

For issues or questions:
1. Check the troubleshooting sections
2. Review AWS CloudWatch logs and metrics
3. Verify all prerequisites are met
4. Ensure proper step execution order

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
