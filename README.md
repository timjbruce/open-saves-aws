# Open Saves AWS

This repository contains the AWS implementation of Open Saves, a cloud-based storage solution for game save data.

## Architecture

Open Saves AWS uses the following AWS services:
- Amazon EKS for container orchestration
- Amazon ECR for container registry
- Amazon DynamoDB for metadata and small record storage
- Amazon S3 for blob storage
- Amazon ElastiCache Redis for caching

## Deployment

Open Saves AWS supports both AMD64 (x86_64) and ARM64 (Graviton) architectures. The deployment is split into discrete steps to allow for better control and troubleshooting.

### Prerequisites

Before deploying, ensure you have the following tools installed:
- AWS CLI (configured with appropriate credentials)
- kubectl
- eksctl
- Docker
- Go (version 1.20 or later)

### Deployment Steps

The deployment process is split into the following steps:

#### Step 1: Deploy VPC, EKS cluster, and ECR registry

```bash
cd aws
./deploy-steps.sh
# Select option 1
```

This step creates:
- An Amazon ECR repository for container images
- An EKS cluster with VPC, subnets, and security groups
- No compute nodes are deployed at this stage

#### Step 2: Deploy S3 bucket, DynamoDB tables, and ElastiCache Redis

```bash
cd aws
./deploy-steps.sh
# Select option 2
# Choose architecture (AMD64 or ARM64)
```

This step creates:
- DynamoDB tables for stores, records, and metadata
- S3 bucket for blob storage
- ElastiCache Redis cluster (architecture-specific)

#### Step 3: Build and push container images

```bash
cd aws
./deploy-steps.sh
# Select option 3
# Choose architecture (AMD64, ARM64, or both)
```

This step:
- Builds the Open Saves application
- Creates Docker images for the selected architecture(s)
- Pushes the images to ECR

#### Step 4: Deploy compute nodes and application

```bash
cd aws
./deploy-steps.sh
# Select option 4
# Choose architecture (AMD64, ARM64, or both)
```

This step:
- Creates EKS node groups with the appropriate instance types
- Deploys the Open Saves application to the cluster
- Sets up services and load balancers

#### Step 5: Run tests

```bash
cd aws
./deploy-steps.sh
# Select option 5
```

This step runs tests against the deployed environment to verify functionality.

### Teardown

To tear down the environment, use the teardown-steps.sh script:

```bash
cd aws
./teardown-steps.sh
# Select options 1-6 in sequence, or option 7 to tear down everything at once
```

## Architecture Differences

### AMD64 (x86_64)
- Uses t3.medium instances for EKS nodes
- Uses cache.t3.small for ElastiCache Redis

### ARM64 (Graviton)
- Uses t4g.medium instances for EKS nodes
- Uses cache.t4g.small for ElastiCache Redis

## Configuration

The configuration for Open Saves is stored in `aws/config/config.yaml`. This file is automatically updated during deployment with the correct endpoints and resource names.

## Troubleshooting

### Common Issues

1. **Invalid Image Name**: If pods are stuck in "InvalidImageName" status, check that the ECR repository URI is correctly set in the deployment.

2. **Redis Connection Issues**: Verify that the Redis endpoint in config.yaml is correct and that the security group allows access from the EKS nodes.

3. **Permission Errors**: Ensure that the IAM roles have the necessary permissions for DynamoDB, S3, and other AWS services.

### Logs

To view logs from the Open Saves pods:

```bash
kubectl logs -n open-saves <pod-name>
```

## Contributing

Please see CONTRIBUTING.md for details on how to contribute to this project.

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
