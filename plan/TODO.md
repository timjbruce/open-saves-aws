# TODO's for AWS Open Saves Migration

This file contains the list of items that still need to be accomplished to complete the migration for Open Saves to AWS. This file will be used, section by section, to accomplish the tasks. A single section must be acknowledged by a human as being completed before the next can start, denoted by the text "Completed" next to the L2 Header. When a section is ready for testing, it should be marked as "Ready to Test" on the L2 Header.

As steps are complete, add the text " - Ready to Test" at the end of each line. If an error occurs, add the text " - Error" at the end of that line and stop processing.

If the line is marked as " - Complete," do not take any action against that item nor adjust anything that might impact that item.

Ensure the proper git branch is used. Only push code when the section or step is marked as "Ready for Validation".

## Conversion and Improvement Work
This section highlights work that will be done in the /open-saves-aws/aws directory structure. Any work listed here should only create/modify/delete files in this directory structure for the project unless it is to create a plan, which will be added to the /aws-open-saves/plan directory.

### ARM Conversion - Complete
This conversion will allow open saves to run on either AMD64 architecture or ARM64 architecture. The end users will not see any difference.

#### git branch
arm64_conversion

#### Steps for ARM Conversion
1. Split up the deployment into discreet steps. Each step should have it's own script file. The architecture parameter should be the same for all files. - Ready
  1. Deploy VPC, EKS cluster, and ECR registry. No compute nodes are needed at this point. - Complete
  2. Deploy S3 bucket, DynamoDB tables, and ElastiCache Redis.  The Redis instance should be selected based on the architecture of choice. - Complete
  3. Build and push the container to the ECR registry, following the architecture of choice. - Complete
  4. Deploy nodes, node groups, roles, and policies for appropriate architecture of choice. Schedule the pods for the container image pushed in step 3. - Complete
  5. Deploy WAF and CloudFront for enhanced security and performance. - Ready
  6. Build tear down scripts for each of the above items. Teardown should happen in the reverse steps. - Complete


#### Bugs to fix
1. ECR repository was not saved to config.yaml when it was created. - Ready
2. Container image name was not saved to config.yaml when it was pushed to the repo. - Ready
3. If the container image is not valid, the scheduling of pods should report an error and stop. - Ready

#### Testing
1. Deployed
2. Testing run successfully

#### Requirements
1. The architectures are AMD64 and ARM64. Both architectures must match at the API interface layer. - Ready
2. The interface to the scrips must use the same name parameters. - Ready
3. Steps should be easy to figure out for the user. - Ready
4. README.md should be updated with the deployment steps - Ready

### Terraform Deploy - Complete
Instead of using scripts to deploy resources, different Terraform scripts. Use the same steps as identified in the ARM Conversion section.

1. Convert script to different Terraform deployment modules - Ready
2. Update the README.md file with the updated deployment process - Ready
3. Terraform modules should be setup in a /terraform directory - Ready
4. Update step 2 to use Parameter Store instead of a local yaml file - Ready
5. Update any steps that needed the local yaml file input to use parameter store - Ready
6. Split the current deployment into separate steps and scripts. These should be uniquely identified. Any outputs needed between steps must be stored in Systems Manager Parameter Store.
  1. Create the EKS cluster, ECR repository as the base infrastructure layer
  2. Create the data tier of S3 bucket, DynamoDB tables, and ElastiCache Redis cluster.
    1. This step needs an architecture flag to identify the right server type for ElastiCache
  3. Create the compute nodes for the EKS cluster
    1. This step needs an architecture flag to identify the right server type for the cluster
  4. Build and push the container image, deploy it to pods in the EKS cluster.
    1. This step needs an architecture flag to identify the right build for the container image
7. The teardown of the architecture must follow the same steps as the deployment

#### git branch
arm64_conversion

#### Bugs to fix
none


### Security Improvements
The solution is highly suspect and allows overly permissive policies for features. These must be improved.

#### git branch
security

#### Steps for Security Audit
1. Audit the existing architecture and identify additional security improvements. Place these as as new section "Items found during security audit" under the Security improvements. Also, for each item found in the security audit, create a section with the title of the security item plus the word "plan." In that section, highlight how you plan to address each of the items from the audit.
2. The security audit only needs to occur on the aws directory. The gcp directory must be ignored.
3. For each of the items in the "Items to fix" section, also create a plan section detailing how to address them.

#### Items to fix
1. Improve security for DynamoDB permissions given to the pods. These should be limited to the tables and actions required.
2. Improve security for S3 permissions given to the pods. These should be limted to the bucket(s) and actions required.
3. Improve the S3 bucket policy to limit the acces to the role for the EKS pods.

#### Items found during security audit
1. Overly permissive DynamoDB permissions
2. Overly permissive S3 permissions
3. Overly permissive ElastiCache permissions
4. Overly permissive SSM Parameter Store permissions
5. Missing S3 bucket security configurations
6. Overly permissive Redis security group
7. Missing S3 bucket policy

#### Overly permissive DynamoDB permissions plan
Modify the `dynamodb_policy` in `step4-compute-app/main.tf` to restrict permissions to only the necessary actions:
```hcl
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "open-saves-dynamodb-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem"
        ]
        Effect   = "Allow"
        Resource = var.dynamodb_table_arns
      }
    ]
  })
}
```
1. Stores Table (s.storesTable):
   • PutItemWithContext - Used in CreateStore
   • GetItemWithContext - Used in GetStore
   • ScanWithContext - Used in ListStores
   • DeleteItemWithContext - Used in DeleteStore

2. Records Table (s.recordsTable):
   • PutItemWithContext - Used in CreateRecord
   • GetItemWithContext - Used in GetRecord
   • QueryWithContext - Used in QueryRecords and DeleteStore (to find records to delete)
   • UpdateItemWithContext - Used in UpdateRecord
   • DeleteItemWithContext - Used in DeleteRecord
   • BatchWriteItemWithContext - Used in DeleteStore (to batch delete records)

3. Metadata Table (s.metadataTable):
   • PutItemWithContext - Used in CreateStore, CreateRecord, DeleteRecord, and SetMetadata
   • GetItemWithContext - Used in CreateRecord, DeleteRecord, and GetMetadata
   • DeleteItemWithContext - Used in DeleteStore and DeleteMetadata
   • QueryWithContext - Used in QueryMetadata


#### Overly permissive S3 permissions plan
Modify the `s3_policy` in `step4-compute-app/main.tf` to restrict permissions to only the necessary actions:
```hcl
resource "aws_iam_role_policy" "s3_policy" {
  name = "open-saves-s3-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:HeadObject",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListObjectsV2"
        ]
        Effect   = "Allow"
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}
```

#### Overly permissive ElastiCache permissions plan
Remove the `elasticache_policy` from `step4-compute-app/main.tf` as it's not needed for the application to function.

#### Overly permissive SSM Parameter Store permissions plan
Modify the `ssm_policy` in `step4-compute-app/main.tf` to restrict access to only the necessary parameters:
```hcl
resource "aws_iam_role_policy" "ssm_policy" {
  name = "open-saves-ssm-policy-${var.architecture}"
  role = aws_iam_role.service_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:*:parameter/open-saves/*"
      }
    ]
  })
}
```

#### Missing S3 bucket security configurations plan
Add server-side encryption, public access blocking, and versioning to the S3 bucket in `step2-infrastructure/main.tf`:
```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "blobs" {
  bucket                  = aws_s3_bucket.blobs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

#### Overly permissive Redis security group plan
Modify the Redis security group in `step2-infrastructure/main.tf` to only allow access from the EKS cluster security group:
```hcl
resource "aws_security_group" "redis" {
  name        = "open-saves-redis-sg"
  description = "Security group for Open Saves Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

#### Missing S3 bucket policy plan
Add an S3 bucket policy in `step2-infrastructure/main.tf` to restrict access to the EKS pods role:
```hcl
resource "aws_s3_bucket_policy" "blobs" {
  bucket = aws_s3_bucket.blobs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = var.service_account_role_arn
        }
        Action = [
          "s3:HeadObject",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListObjectsV2"
        ]
        Resource = [
          aws_s3_bucket.blobs.arn,
          "${aws_s3_bucket.blobs.arn}/*"
        ]
      },
      {
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.blobs.arn,
          "${aws_s3_bucket.blobs.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = var.service_account_role_arn
          }
        }
      }
    ]
  })
}
```


### Cost Optimization
The solution is questionable for cost management. Analyze the solution and determine any possible cost savings that can be implemented.

#### git branch
cost_optimization

#### Steps for Cost Optimization
1. Audit the solution and place any cost findings in point 2 below.
2. Items found during cost optimization audit

### Load Testing - Complete
This section will generate dashboards and load testing scripts for the solution, using the Python Locust framework. Load testing will utilize a /testing/load directory under the aws portion of this project. Load testing should support the ability to scale up to 5000 requests / second. Load testing must not update steps 1 through 5. A 6th step should be created for the dashboards. Any deployments for load testing should be done in the /testing/load directory.

#### git branch
load_testing

#### Steps for load testing
1. Generate dashboard to monitor pods, DynamoDB tables, S3 bucket, and ElastiCache redis instance. This should follow the AWS blueprints for Observability at https://aws-samples.github.io/cdk-eks-blueprints-patterns/patterns/observability/existing-eks-awsnative-observability/ - Complete
2. Generate Python Locust scripts to send traffic to the solution, with targets of 100, 500, 1000, and 5000 request per second, using a variety of calls that can be loaded from json files and modified to create a level of randonmess and exercise the subsystems within the open saves architecture. - Complete
3. Record and analyze the results. - Complete


## Testing
Run all these steps. Highlight the results of testing at the end of the steps. If any errors occur, stop processing and do not fix anything. If there are any issues, stop processing and do not take any manual steps. Highlight the current issue and wait for further instruction. The test script is open-saves-test.sh.

Only a summary of what you did and the results of testing, if any was performed should be reviewed.

The architecture for ElastiCache redis should not be used to determine the nodes to deploy to EKS.

### Base deploy
1. Deploy Step 1 (Base Infrastructure) - once per environment
2. Deploy Step 2 (Data Layer) for ARM64 - once per environment

### Teardown any existing environment
1. Empty the s3 bucket
2. Delete all container images from the ECR repo for this project
3. Teardown Step 5 (CloudFront & WAF) for the current architecture using the teardown script
4. Teardown Step 4 (Compute App) for the current architecture using the teardown script
5. Destroy Step 3 (Container Images) for the current architecture using the teardown script

### Test AMD64
1. Deploy Step 3 (Container Images) with AMD64 using the deploy script
2. Deploy Step 4 (Compute App) with AMD64 using the deploy script
3. Deploy Step 5 (CloudFront & WAF) using the deploy script 
4. Run the Test Script for the AMD64 environment

### Test ARM64
1. Deploy Step 3 (Container Images) with ARM64 using the deploy script
2. Deploy Step 4 (Compute App) with ARM64 using the deploy script
3. Deploy Step 5 (CloudFront & WAF) using the deploy script
4. Run the Test Script for the ARM64 environment

### Run the Test Script only
1. Run the Test Script for the currently deployed environment

### Architecture Switch Demo (New Capability)
1. Deploy complete environment with ARM64: `./deploy-architecture.sh full-deploy arm64`
2. Run test script and record results
3. Switch to AMD64: `./deploy-architecture.sh switch-arch amd64` 
4. Run test script and record results
5. Switch back to ARM64: `./deploy-architecture.sh switch-arch arm64`
6. Run test script and record results
7. Verify CloudFront URL remains the same throughout all switches
