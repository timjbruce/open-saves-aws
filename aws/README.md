# AWS Open Saves - Dual Database Implementation

This directory contains two complete implementations of Open Saves for AWS, each using a different database backend.

## Architecture Overview

```
aws/
├── shared/          # Shared testing scripts and utilities
├── dynamodb/        # Complete DynamoDB implementation
└── documentdb/      # Complete DocumentDB implementation
```

## Implementation Options

### DynamoDB Implementation (`/aws/dynamodb/`)
- **Database**: Amazon DynamoDB (NoSQL)
- **Features**: Serverless, auto-scaling, pay-per-request
- **Best For**: Variable workloads, serverless architectures
- **Deployment**: `cd dynamodb && ./terraform/deploy-full.sh --architecture amd64`

### DocumentDB Implementation (`/aws/documentdb/`)
- **Database**: Amazon DocumentDB (MongoDB-compatible)
- **Features**: Managed MongoDB, cluster-based, consistent performance
- **Best For**: MongoDB workloads, predictable performance needs
- **Deployment**: `cd documentdb && ./terraform/deploy-full.sh --architecture amd64`

## Shared Components

### Testing Scripts (`/aws/shared/`)
Both implementations use the same testing infrastructure:
- `api-test.sh` - Comprehensive API testing
- `open-saves-test.sh` - Main test suite
- `open-saves-test-universal.sh` - Universal test script
- `simple-api-test.sh` - Basic API validation
- `final-test.sh` - Final validation tests
- `testing/` - Load testing with Locust framework

## Key Features (Both Implementations)

- **Multi-Architecture Support**: AMD64 and ARM64 with easy switching
- **Production Ready**: CloudFront CDN, WAF protection, comprehensive monitoring
- **Independent Deployment**: 5 separate Terraform steps for modular deployment
- **Complete API Compatibility**: Both implementations provide identical APIs
- **Security First**: Least-privilege IAM policies, encryption at rest and in transit
- **Load Testing**: Built-in load testing framework supporting up to 5000 RPS

## Quick Start

### Choose Your Implementation:

**For DynamoDB:**
```bash
cd aws/dynamodb
./terraform/deploy-full.sh --architecture amd64
```

**For DocumentDB:**
```bash
cd aws/documentdb  
./terraform/deploy-full.sh --architecture amd64
```

### Run Tests:
```bash
cd aws/shared
./api-test.sh <endpoint-url>
```

## Architecture Switching

Both implementations support easy architecture switching between AMD64 and ARM64:

```bash
# Switch DynamoDB to ARM64
cd aws/dynamodb
./terraform/switch-architecture.sh --to-arch arm64

# Switch DocumentDB to ARM64  
cd aws/documentdb
./terraform/switch-architecture.sh --to-arch arm64
```

## Implementation Details

### DynamoDB Implementation
- **Tables**: 3 DynamoDB tables (stores, records, metadata)
- **Scaling**: Automatic with on-demand billing
- **Consistency**: Eventually consistent reads, strongly consistent writes
- **Backup**: Point-in-time recovery enabled

### DocumentDB Implementation  
- **Collections**: MongoDB collections in DocumentDB cluster
- **Scaling**: Manual cluster scaling
- **Consistency**: Strong consistency within cluster
- **Backup**: Automated backups with configurable retention

## Testing Both Implementations

The shared testing framework allows you to validate both implementations:

```bash
# Test DynamoDB implementation
cd aws/shared
./api-test.sh https://your-dynamodb-endpoint.com

# Test DocumentDB implementation  
cd aws/shared
./api-test.sh https://your-documentdb-endpoint.com
```

## Performance Comparison

| Feature | DynamoDB | DocumentDB |
|---------|----------|------------|
| **Latency** | Sub-millisecond | Low millisecond |
| **Throughput** | Unlimited (on-demand) | Instance-dependent |
| **Scaling** | Automatic | Manual |
| **Cost Model** | Pay-per-request | Fixed instance cost |
| **Consistency** | Eventually consistent | Strongly consistent |

## Support

Both implementations provide identical Open Saves APIs and feature sets. Choose based on your specific requirements:

- **DynamoDB**: For serverless, variable workloads
- **DocumentDB**: For MongoDB compatibility, predictable performance

For detailed implementation-specific documentation, see the README files in each implementation directory.
