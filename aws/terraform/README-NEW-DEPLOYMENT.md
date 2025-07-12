# Open Saves - New Architecture-Agnostic Deployment

This document describes the new deployment process that allows switching between AMD64 and ARM64 architectures without destroying the CloudFront distribution.

## Overview

The deployment has been reorganized into 5 discrete steps:

1. **Step 1: Base Infrastructure** - VPC, EKS cluster, ECR repository (deploy once)
2. **Step 2: Data Layer** - S3 bucket, DynamoDB tables, Redis cluster (deploy once)
3. **Step 3: CloudFront & WAF** - CloudFront distribution and WAF (deploy once per environment)
4. **Step 4: Container Images** - Build and push container images (deploy per architecture)
5. **Step 5: Compute App** - EKS nodes and application pods (deploy per architecture)

## Key Benefits

- **No CloudFront Recreation**: CloudFront is architecture-agnostic and persists across architecture switches
- **Faster Architecture Switching**: Only Steps 4-5 need to be redeployed when switching architectures
- **Cost Savings**: Avoid CloudFront distribution recreation costs and downtime
- **Modular Deployment**: Deploy only what you need for testing or development

## Quick Start

### Full Deployment
```bash
# Deploy complete environment with ARM64
./deploy-architecture.sh full-deploy arm64

# Deploy complete environment with AMD64
./deploy-architecture.sh full-deploy amd64
```

### Architecture Switching (Recommended)
```bash
# Switch from current architecture to AMD64 (keeps CloudFront)
./deploy-architecture.sh switch-arch amd64

# Switch from current architecture to ARM64 (keeps CloudFront)
./deploy-architecture.sh switch-arch arm64
```

### Individual Steps
```bash
# Deploy base infrastructure
./deploy-step1.sh

# Deploy data layer
./deploy-step2.sh

# Build and push container images
./deploy-step4.sh

# Deploy compute resources
./deploy-step5.sh

# Deploy CloudFront (after compute is ready)
./deploy-step3.sh
```

## Environment Variables

Set these in `.env.deploy` or export them:

```bash
export AWS_REGION=us-west-2
export ENVIRONMENT=dev
export ARCHITECTURE=arm64  # or amd64
```

## Deployment Order

### Initial Deployment
1. Step 1: Base Infrastructure
2. Step 2: Data Layer  
3. Step 4: Container Images
4. Step 5: Compute App
5. Step 3: CloudFront & WAF (requires load balancer from Step 5)

### Architecture Switch
1. Teardown Step 5: Remove current compute resources
2. Deploy Step 4: Build new container images for target architecture
3. Deploy Step 5: Deploy new compute resources
4. Step 3 remains unchanged (CloudFront continues working)

### Complete Teardown
1. Step 5: Compute App
2. Step 4: Container Images
3. Step 3: CloudFront & WAF
4. Step 2: Data Layer
5. Step 1: Base Infrastructure

## Architecture-Specific Resources

### Persistent (Architecture-Agnostic)
- VPC and networking
- EKS cluster control plane
- ECR repository
- S3 bucket
- DynamoDB tables
- CloudFront distribution
- WAF rules

### Per-Architecture
- EKS node groups (different instance types)
- Container images (different builds)
- Application pods
- Redis cluster (different instance types)

## Testing Workflow

The new workflow for your TODO.md testing section becomes:

```bash
# Initial setup (once)
./deploy-architecture.sh full-deploy arm64

# Test ARM64
./open-saves-test.sh

# Switch to AMD64 (fast - no CloudFront recreation)
./deploy-architecture.sh switch-arch amd64

# Test AMD64  
./open-saves-test.sh

# Switch back to ARM64 (fast)
./deploy-architecture.sh switch-arch arm64

# Test ARM64 again
./open-saves-test.sh
```

## Troubleshooting

### CloudFront Deployment Fails
- Ensure Step 5 (Compute App) is deployed first
- Check that load balancer is accessible
- Verify security groups allow CloudFront IP ranges

### Architecture Switch Issues
- Ensure previous compute resources are fully torn down
- Check ECR repository has space for new images
- Verify EKS cluster has capacity for new node groups

### Module Not Found Errors
- Run `terraform init` after the reorganization
- Check that all module paths are correct in main.tf

## Migration from Old Structure

If you have an existing deployment with the old structure:

1. **Backup current state**: `cp terraform.tfstate terraform.tfstate.backup`
2. **Run terraform init**: `terraform init` (to recognize new modules)
3. **Import existing resources**: Use `terraform import` for critical resources if needed
4. **Gradual migration**: Deploy new structure alongside old, then migrate traffic

## Cost Optimization

- **CloudFront**: Deploy once, use for all architectures
- **Data Layer**: Shared across architectures
- **Compute**: Only pay for active architecture
- **Development**: Use `teardown-arch` to remove unused architectures

## Security Notes

- CloudFront WAF rules are environment-specific, not architecture-specific
- Security groups are properly configured for CloudFront IP ranges
- Origin verification headers prevent direct load balancer access
