# Open Saves Load Testing

This directory contains scripts and configurations for load testing the Open Saves API using Locust.

## Architecture

The load testing environment consists of:

1. **EC2 Instances**: 
   - One master instance running the Locust web UI
   - Multiple worker instances generating load

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform installed
- Open Saves deployed with CloudFront endpoint available

## Deployment

### Step 1: Deploy S3 Bucket for Locust Scripts

First, deploy the S3 bucket that will store the Locust scripts:

```bash
./deploy-s3-bucket.sh [--region REGION]
```

Optional parameters:
- `--region`: AWS region to deploy to (default: from AWS config or us-west-2)

This script will:
1. Create an S3 bucket for storing Locust scripts
2. Upload the Locust Python scripts and shell scripts to the bucket
3. Configure the bucket for EC2 instance access

### Step 2: Deploy EC2 Locust Infrastructure

```bash
./deploy-ec2-locust.sh --endpoint ENDPOINT [options]
```

Required parameters:
- `--endpoint`: CloudFront endpoint for Open Saves (e.g., dlwqqp0bucqw2.cloudfront.net)

Optional parameters:
- `--region`: AWS region to deploy to (default: from AWS config or us-west-2)
- `--worker-count`: Number of Locust worker instances (default: 3)
- `--instance-type`: EC2 instance type for workers (default: c5.large)
- `--distribution-id`: CloudFront distribution ID (default: EV2NR6DUG279M)

This script will:
1. Deploy a VPC with public subnets
2. Launch EC2 instances for Locust master and workers
3. Configure the instances with the Locust script embedded in user data
4. Create a CloudWatch dashboard for monitoring

## Accessing the Locust Web UI

After deployment, the script will output the URL for the Locust web UI:

```
Locust web UI: http://<master-instance-public-ip>:8089
```

Use this URL to access the Locust web UI and start load tests.

## Monitoring

A CloudWatch dashboard is created for monitoring the Open Saves environment during load testing. The dashboard URL is provided in the output of the deployment script.

## Cleanup

To clean up all resources created for load testing:

```bash
./cleanup-load-test.sh
```

This script will delete:
1. EC2 instances
2. VPC and networking components
3. CloudWatch dashboard
4. IAM roles and policies
