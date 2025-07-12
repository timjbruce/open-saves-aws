# Open Saves AWS Load Testing Plan

This document outlines the comprehensive plan for load testing the Open Saves AWS implementation. The goal is to verify that the system can handle high throughput (up to 5000 requests per second) while maintaining acceptable performance characteristics.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Observability Setup](#observability-setup)
4. [Load Testing Framework](#load-testing-framework)
5. [Test Scenarios](#test-scenarios)
6. [Implementation Plan](#implementation-plan)
7. [Analysis and Reporting](#analysis-and-reporting)
8. [Scaling Considerations](#scaling-considerations)

## Overview

The load testing will be implemented using Python Locust framework to generate traffic at various levels (100, 500, 1000, and 5000 requests per second). We'll create dashboards to monitor the system's performance during these tests, focusing on the following components:

- EKS pods performance metrics
- DynamoDB table throughput and latency
- S3 bucket operations and throughput
- ElastiCache Redis performance metrics

All load testing code and configurations will be stored in the `/aws/testing/load` directory and will not modify the existing deployment steps (1-5). A new step 6 will be created for the observability dashboards.

## Prerequisites

Before starting the load testing, ensure:

1. A fully deployed Open Saves AWS environment (Steps 1-5)
2. AWS CLI configured with appropriate permissions
3. Python 3.8+ installed
4. Access to CloudWatch and Container Insights
5. Sufficient AWS service quotas to handle the load

## Observability Setup

### Dashboard Creation (Step 6)

We'll implement observability following the AWS EKS Blueprints for Observability pattern. This includes:

1. **CloudWatch Container Insights** - For EKS cluster monitoring
2. **Custom CloudWatch Dashboards** - For integrated views of all components
3. **X-Ray Tracing** - For request path analysis
4. **CloudWatch Alarms** - For performance thresholds

#### Dashboard Components:

1. **EKS Pod Dashboard**
   - CPU and memory utilization
   - Pod restart count
   - Request latency
   - Error rates
   - Network I/O

2. **DynamoDB Dashboard**
   - Read/write capacity units consumed
   - Throttled requests
   - Successful request latency (p50, p90, p99)
   - Table size metrics

3. **S3 Dashboard**
   - Request rates
   - Error rates
   - First byte latency
   - Total bytes transferred

4. **ElastiCache Redis Dashboard**
   - CPU utilization
   - Memory usage
   - Cache hit/miss ratio
   - Network throughput
   - Connection count

### Implementation Options

**Option 1: CloudWatch Dashboard JSON**
- Create CloudWatch dashboards using JSON definitions
- Pros: Simple, direct AWS integration
- Cons: Limited visualization options

**Option 2: AWS Managed Grafana**
- Deploy AWS Managed Grafana with CloudWatch data source
- Pros: Rich visualization, better dashboarding
- Cons: Additional service to manage

**Option 3: Prometheus + Grafana on EKS**
- Deploy Prometheus and Grafana in the EKS cluster
- Pros: Industry standard, highly customizable
- Cons: More complex setup, requires cluster resources

**Recommendation:** Implement Option 2 (AWS Managed Grafana) for the best balance of features and management overhead.

## Load Testing Framework

### Locust Setup

We'll use Locust for load testing with the following components:

1. **Locust Master** - Coordinates the test and provides the web UI
2. **Locust Workers** - Generate the load (multiple workers for high RPS)
3. **Test Scenarios** - Python scripts defining user behaviors

### Deployment Options

**Option 1: EC2-based Locust**
- Deploy Locust on EC2 instances
- Pros: Simple setup, direct control
- Cons: Manual scaling, instance management

**Option 2: EKS-based Locust**
- Deploy Locust in the same EKS cluster
- Pros: Kubernetes management, easy scaling
- Cons: Potential resource contention with the system under test

**Option 3: Distributed Locust with AWS Fargate**
- Deploy Locust master on EC2, workers on Fargate
- Pros: Serverless workers, automatic scaling
- Cons: More complex setup

**Recommendation:** Implement Option 3 for high-scale testing (5000 RPS) to ensure the load generators themselves don't become a bottleneck.

## Test Scenarios

We'll implement the following test scenarios to exercise all aspects of the Open Saves system:

### 1. Basic CRUD Operations

- Create/read/update/delete stores
- Create/read/update/delete records
- Set/get/delete metadata

### 2. Blob Storage Operations

- Upload blobs of various sizes (1KB, 100KB, 1MB, 10MB)
- Download blobs
- Delete blobs

### 3. Query Operations

- Query records by owner
- Query records by tags
- Query metadata

### 4. Mixed Workload

- Realistic mix of all operations based on expected usage patterns
- Configurable read/write ratios (e.g., 80/20, 95/5)

### 5. Cache Effectiveness

- Repeated reads to measure cache hit rates
- Cache invalidation tests

## Implementation Plan

### Phase 1: Setup (Week 1)

1. Create the `/aws/testing/load` directory structure
2. Set up observability components (Step 6)
3. Implement basic Locust framework
4. Create initial test scenarios

### Phase 2: Development (Week 2)

1. Develop all test scenarios
2. Create JSON-based test data generators
3. Implement randomization for realistic testing
4. Set up distributed Locust deployment

### Phase 3: Testing (Week 3)

1. Run baseline tests at 100 RPS
2. Analyze and optimize
3. Incrementally increase to 500, 1000 RPS
4. Analyze system bottlenecks
5. Scale components as needed
6. Test at 5000 RPS

### Phase 4: Analysis and Documentation (Week 4)

1. Compile test results
2. Create performance analysis report
3. Document scaling recommendations
4. Finalize documentation

## Analysis and Reporting

For each test run, we'll collect and analyze:

1. **Throughput Metrics**
   - Requests per second achieved
   - Success/failure rates

2. **Latency Metrics**
   - Average, median, p95, p99 response times
   - Breakdown by operation type

3. **Resource Utilization**
   - CPU, memory, network usage across all components
   - Database throughput and throttling events
   - Cache hit/miss ratios

4. **Scaling Behavior**
   - How performance scales with increased load
   - Identification of bottlenecks

5. **Cost Analysis**
   - Resource costs during different load levels
   - Cost optimization recommendations

## Scaling Considerations

Based on initial testing, we may need to scale various components:

### DynamoDB Scaling Options

**Option 1: On-demand Capacity**
- Pros: Automatic scaling, no management
- Cons: Potentially higher cost

**Option 2: Provisioned Capacity with Auto Scaling**
- Pros: More cost-effective, predictable
- Cons: Requires configuration, potential for throttling

### EKS Scaling Options

**Option 1: Cluster Autoscaler**
- Automatically adjust node count based on pod demand
- Configure appropriate min/max nodes

**Option 2: Horizontal Pod Autoscaler**
- Scale the number of Open Saves pods based on CPU/memory
- Set target utilization thresholds

### ElastiCache Scaling Options

**Option 1: Vertical Scaling**
- Increase node size for higher throughput
- Pros: Simple, no application changes
- Cons: Limited scalability, potential downtime

**Option 2: Cluster Mode**
- Enable Redis cluster mode for horizontal scaling
- Pros: Higher scalability, no downtime
- Cons: Application may need changes to support sharding

## Directory Structure

```
/aws/testing/load/
├── README.md                    # Setup and usage instructions
├── infrastructure/              # Terraform for observability and load testing infrastructure
│   ├── grafana.tf               # AWS Managed Grafana setup
│   ├── cloudwatch.tf            # CloudWatch dashboard definitions
│   └── locust.tf                # Locust deployment resources
├── dashboards/                  # Dashboard definitions
│   ├── eks_dashboard.json       # EKS monitoring dashboard
│   ├── dynamodb_dashboard.json  # DynamoDB monitoring dashboard
│   ├── s3_dashboard.json        # S3 monitoring dashboard
│   └── redis_dashboard.json     # ElastiCache monitoring dashboard
├── locust/                      # Locust test files
│   ├── locustfile.py            # Main Locust configuration
│   ├── scenarios/               # Test scenarios
│   │   ├── crud_operations.py   # Store and record CRUD tests
│   │   ├── blob_operations.py   # Blob storage tests
│   │   ├── query_operations.py  # Query tests
│   │   └── mixed_workload.py    # Combined realistic workload
│   └── data/                    # Test data
│       ├── stores.json          # Store templates
│       ├── records.json         # Record templates
│       └── blobs/               # Sample blobs of various sizes
└── analysis/                    # Scripts for analyzing results
    ├── process_results.py       # Process and visualize test results
    └── report_template.md       # Template for final report
```

## Next Steps

1. Create the git branch `load_testing`
2. Set up the directory structure
3. Begin implementing the observability components
4. Develop the initial Locust test framework

This plan provides a comprehensive approach to load testing the Open Saves AWS implementation, with multiple options for implementation and a clear path to achieving the 5000 RPS target.
