# Open Saves - AWS DocumentDB Implementation

This directory contains the DocumentDB implementation of Open Saves for AWS, as an alternative to the DynamoDB implementation in the `/aws` directory.

## Key Differences from DynamoDB Implementation

### Architecture Changes
- **DocumentDB** replaces DynamoDB for metadata and record storage
- **MongoDB-compatible queries** instead of DynamoDB operations
- **VPC-only deployment** (DocumentDB requires VPC)
- **Connection pooling** for database connections
- **Document-based data model** instead of key-value

### Benefits of DocumentDB
- **Rich querying capabilities** with MongoDB query language
- **ACID transactions** across multiple documents
- **Flexible schema** for evolving game data structures
- **Aggregation pipelines** for complex analytics
- **Better support for nested data structures**

### Trade-offs
- **Higher baseline cost** (minimum cluster size)
- **VPC requirement** (no serverless option)
- **Connection management** complexity
- **Different scaling characteristics**

## Directory Structure

```
aws-documentdb/
├── terraform/
│   ├── step1-base-infrastructure/    # EKS, ECR, VPC
│   ├── step2-infrastructure/         # DocumentDB, S3, ElastiCache
│   ├── step3-container-images/       # Build & push containers
│   ├── step4-compute-app/           # Deploy app with DocumentDB config
│   └── step5-cloudfront-waf/        # CDN and security
├── server/                          # Go application code
│   ├── documentdb_store.go          # DocumentDB implementation
│   ├── documentdb_store_test.go     # Tests
│   └── ...
├── deploy-full.sh                   # Full deployment script
├── switch-architecture.sh           # Architecture switching
└── testing/                         # Load testing scripts
```

## Quick Start

```bash
cd aws-documentdb/terraform

# Deploy everything for AMD64
./deploy-full.sh --architecture amd64

# Or deploy individual steps
./deploy-step1.sh  # EKS Cluster & ECR
./deploy-step2.sh --architecture amd64  # DocumentDB, S3, Redis
./deploy-step3.sh --architecture amd64  # Container Images
./deploy-step4.sh --architecture amd64  # Compute & Application
./deploy-step5.sh --architecture amd64  # CloudFront & WAF
```

## DocumentDB Configuration

The DocumentDB cluster is configured with:
- **Multi-AZ deployment** for high availability
- **Encryption at rest and in transit**
- **Automated backups** with point-in-time recovery
- **Performance monitoring** with CloudWatch
- **Security groups** restricting access to EKS pods only

## Migration from DynamoDB

If you have an existing DynamoDB deployment and want to migrate:

1. **Export data** from DynamoDB tables
2. **Transform data** to DocumentDB document format
3. **Import data** into DocumentDB collections
4. **Update application** to use DocumentDB endpoints
5. **Test thoroughly** before switching traffic

See `migration/` directory for migration scripts and documentation.

## Cost Considerations

DocumentDB has different cost characteristics than DynamoDB:
- **Fixed cluster costs** vs pay-per-request
- **Storage costs** for data and backups
- **I/O costs** for read/write operations
- **Cross-AZ data transfer** costs

Use the AWS Pricing Calculator to estimate costs for your workload.

## Monitoring and Observability

DocumentDB provides rich monitoring through:
- **CloudWatch metrics** for cluster performance
- **Performance Insights** for query analysis
- **Slow query logs** for optimization
- **Connection monitoring** for pool management

## Next Steps

1. Review the implementation differences
2. Test with your specific workload
3. Compare performance and costs
4. Plan migration strategy if needed
