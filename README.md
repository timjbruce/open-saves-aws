# Open Saves

This repository contains implementations of Open Saves, a cloud-based storage solution for game save data.

## Overview

Open Saves is a specialized storage system designed for game developers to store and manage game save data in the cloud. It provides a unified API for storing both structured and unstructured data, with implementations for different cloud providers.

## Implementations

### AWS Implementation

The AWS implementation of Open Saves is located in the `/aws` directory. It uses AWS services such as:
- Amazon EKS for container orchestration
- Amazon DynamoDB for metadata and small record storage
- Amazon S3 for blob storage
- Amazon ElastiCache Redis for caching
- Amazon CloudFront and WAF for security and performance

**Key Features:**
- **Independent Terraform Steps**: 5 completely independent deployment steps
- **Architecture Support**: Full AMD64 and ARM64 support with easy switching
- **Security First**: Principle of least privilege IAM policies, WAF protection
- **Production Ready**: CloudFront CDN, comprehensive monitoring, automated teardown

**Quick Start:**
```bash
cd aws/terraform

# Deploy everything for AMD64
./deploy-full.sh --architecture amd64

# Or deploy individual steps
./deploy-step1.sh  # EKS Cluster & ECR
./deploy-step2.sh --architecture amd64  # Data Infrastructure
./deploy-step3.sh --architecture amd64  # Container Images
./deploy-step4.sh --architecture amd64  # Compute & Application
./deploy-step5.sh --architecture amd64  # CloudFront & WAF

# Switch architectures easily
./switch-architecture.sh --to-arch arm64
```

For detailed information about the AWS implementation, see the [AWS README](/aws/README.md).

### GCP Implementation

The GCP implementation of Open Saves is located in the `/gcp` directory. It uses Google Cloud Platform services such as:
- Google Kubernetes Engine for container orchestration
- Firestore for metadata and small record storage
- Cloud Storage for blob storage
- Memorystore Redis for caching

For detailed information about the GCP implementation, see the [GCP README](/gcp/README.md).

## Architecture

Open Saves follows a cloud-native architecture with the following components:

1. **API Layer**: gRPC service that exposes the Open Saves API
2. **Metadata Store**: For storing metadata about stores and records
3. **Blob Storage**: For storing large binary objects
4. **Cache Layer**: For improving performance of frequently accessed data
5. **Security Layer**: WAF and CDN for protection and performance (AWS)

## Key Features

- **Multi-Architecture Support**: Deploy on AMD64 or ARM64 with easy switching
- **Store and retrieve game save data**: Structured metadata and binary blobs
- **Efficient caching**: Redis-based caching for improved performance
- **Scalable architecture**: Auto-scaling for high-traffic games
- **Security focused**: WAF protection, least-privilege IAM policies
- **Production ready**: CloudFront CDN, comprehensive monitoring
- **Easy deployment**: Independent Terraform steps with master orchestration scripts

## Deployment Models

### AWS - Independent Steps Approach
- 5 completely independent Terraform configurations
- Steps communicate via AWS SSM Parameter Store
- No top-level Terraform orchestration
- Easy architecture switching and selective deployment

### GCP - Traditional Approach
- Single Terraform configuration
- Direct resource dependencies
- Simpler for basic deployments

## Getting Started

1. **Choose your cloud provider** (AWS recommended for production)
2. **Follow the provider-specific README** for detailed instructions
3. **Deploy the infrastructure** using the provided scripts
4. **Test the API** using the included test scripts
5. **Monitor and scale** as needed

## Contributing

Please see CONTRIBUTING.md for details on how to contribute to this project.

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
