# Open Saves AWS Implementation

This is the AWS implementation of Open Saves, a cloud-based storage solution for game save data.

## Overview

Open Saves AWS uses the following AWS services:
- Amazon EKS for container orchestration
- Amazon DynamoDB for metadata and small record storage
- Amazon S3 for blob storage
- Amazon ElastiCache Redis for caching

## Architecture

The Open Saves AWS implementation follows a modular architecture with the following components:

1. **EKS Cluster and ECR Registry**: The foundational infrastructure including VPC, subnets, EKS cluster, and ECR repository.
2. **Infrastructure Layer**: DynamoDB tables, S3 bucket, and ElastiCache Redis cluster.
3. **Container Images**: Open Saves application container images stored in ECR.
4. **Compute Layer**: EKS node groups, application pods, and services.

## Deployment

The deployment is managed through Terraform and is divided into discrete steps that can be executed individually.

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed (version 1.0.0 or later)
- Docker installed (for building container images)
- kubectl installed (for interacting with the Kubernetes cluster)

### Deployment Steps

Use the `scripts/deploy-targeted.sh` script to deploy each step individually:

```bash
./scripts/deploy-targeted.sh --step <step_number> --arch <architecture>
```

Where:
- `<step_number>` is one of: 1, 2, 3, 4, or "all"
- `<architecture>` is one of: amd64, arm64, or both

#### Examples

1. Deploy only the EKS cluster and ECR registry:
   ```bash
   ./scripts/deploy-targeted.sh --step 1 --arch amd64
   ```

2. Deploy only the infrastructure components:
   ```bash
   ./scripts/deploy-targeted.sh --step 2 --arch arm64
   ```

3. Build and push container images:
   ```bash
   ./scripts/deploy-targeted.sh --step 3 --arch both
   ```

4. Deploy compute nodes and application:
   ```bash
   ./scripts/deploy-targeted.sh --step 4 --arch arm64
   ```

5. Deploy all steps in sequence:
   ```bash
   ./scripts/deploy-targeted.sh --step all --arch amd64
   ```

### Destroying Resources

To destroy resources for a specific step, use the `--destroy` flag:

```bash
./scripts/deploy-targeted.sh --step <step_number> --arch <architecture> --destroy
```

When destroying resources, it's recommended to destroy them in reverse order (4, 3, 2, 1) or use:

```bash
./scripts/deploy-targeted.sh --step all --arch <architecture> --destroy
```

Alternatively, you can use the cleanup script which will destroy all resources:

```bash
./scripts/cleanup.sh
```

## Testing

After deployment, you can run tests using the provided test script:

```bash
./open-saves-test.sh http://<service-url>:8080
```

Replace `<service-url>` with the external endpoint from the service output.

## Configuration

The deployment uses AWS Systems Manager Parameter Store for configuration. This provides a more secure and centralized way to manage configuration.

The Parameter Store parameter is created during Step 2 (Infrastructure) and is used by the application pods deployed in Step 4.

## Verifying the Deployment

After completing Step 4, you can verify the deployment:

1. Configure kubectl to use your EKS cluster:
   ```bash
   aws eks update-kubeconfig --name open-saves-cluster-new --region us-west-2
   ```

2. Check the pods:
   ```bash
   kubectl get pods -n open-saves
   ```

3. Get the service URL:
   ```bash
   kubectl get service -n open-saves
   ```

## Troubleshooting

If you encounter issues during deployment:

1. Check the Terraform state:
   ```bash
   cd terraform
   terraform state list
   ```

2. Check the EKS cluster status:
   ```bash
   aws eks describe-cluster --name open-saves-cluster-new --region us-west-2
   ```

3. Check the logs of the pods:
   ```bash
   kubectl logs -n open-saves <pod-name>
   ```

4. If a step fails, you can retry just that step using the deployment script.

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
