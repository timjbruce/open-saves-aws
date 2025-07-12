# Open Saves AWS Load Testing

This directory contains the load testing framework and observability components for the Open Saves AWS implementation.

## Overview

The load testing framework is designed to test the Open Saves AWS implementation at various load levels, from 100 to 5000 requests per second. It includes:

- Observability dashboards for monitoring system performance
- Locust-based load testing scripts
- Analysis tools for processing and visualizing test results

## Directory Structure

- `infrastructure/`: Terraform files for deploying observability and load testing infrastructure
- `dashboards/`: CloudWatch and Grafana dashboard definitions
- `locust/`: Locust test scripts and data
  - `scenarios/`: Test scenarios for different Open Saves operations
  - `data/`: Test data templates and sample blobs
- `analysis/`: Scripts for analyzing and reporting test results

## Getting Started

1. Ensure you have a fully deployed Open Saves AWS environment (Steps 1-5)
2. Deploy the observability components:
   ```
   cd infrastructure
   terraform init
   terraform apply
   ```
3. Run the load tests:
   ```
   cd locust
   python -m locust -f locustfile.py
   ```

## Test Scenarios

The load testing framework includes the following test scenarios:

1. Basic CRUD operations (stores, records, metadata)
2. Blob storage operations (upload, download, delete)
3. Query operations (by owner, tags, etc.)
4. Mixed workload with configurable read/write ratios

## Observability

The observability components include:

1. CloudWatch dashboards for EKS, DynamoDB, S3, and ElastiCache
2. AWS Managed Grafana for advanced visualization
3. CloudWatch alarms for performance thresholds

## Analysis

After running the tests, use the analysis scripts to process the results:

```
cd analysis
python process_results.py --input-file ../locust/results.csv
```

This will generate visualizations and a summary report of the test results.

## Scaling Recommendations

Based on the test results, you may need to scale various components of the Open Saves AWS implementation. See the LOADTESTING.md file in the plan directory for detailed scaling options and recommendations.
