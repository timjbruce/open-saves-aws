# TODO's for AWS Open Saves Migration

This file contains the list of items that still need to be accomplished to complete the migration for Open Saves to AWS. This file will be used, section by section, to accomplish the tasks. A single section must be acknowledged by a human as being completed before the next can start, denoted by the text "Completed" next to the L2 Header. When a section is ready for testing, it should be marked as "Ready to Test" on the L2 Header.

As steps are complete, add the text " - Ready" at the end of each line. If an error occurs, add the text " - Error" at the end of that line and stop processing.

Ensure the proper git branch is used. Only push code when the section or step is marked as "Ready for Validation".

## ARM Conversion - Completed
This conversion will allow open saves to run on either AMD64 architecture or ARM64 architecture. The end users will not see any difference.

### git branch
arm64_conversion

### Steps for ARM Conversion
1. Split up the deployment into discreet steps. Each step should have it's own script file. The architecture parameter should be the same for all files. - Ready
  1. Deploy VPC, EKS cluster, and ECR registry. No compute nodes are needed at this point. - Ready
  2. Deploy S3 bucket, DynamoDB tables, and ElastiCache Redis.  The Redis instance should be selected based on the architecture of choice. - Ready
  3. Build and push the container to the ECR registry, following the architecture of choice. - Ready
  4. Deploy nodes, node groups, roles, and policies for appropriate architecture of choice. Schedule the pods for the container image pushed in step 3. - Ready
  5. Run a full test of the enviornment. - Ready
  6. Build tear down scripts for each of the above items. Teardown should happen in the reverse steps. - Ready

### Bugs to fix
1. ECR repository was not saved to config.yaml when it was created. - Ready
2. Container image name was not saved to config.yaml when it was pushed to the repo. - Ready
3. If the container image is not valid, the scheduling of pods should report an error and stop. - Ready

### Requirements
1. The architectures are AMD64 and ARM64. Both architectures must match at the API interface layer. - Ready
2. The interface to the scrips must use the same name parameters. - Ready
3. Steps should be easy to figure out for the user. - Ready
4. README.md should be updated with the deployment steps - Ready

## Terraform Deploy
Instead of using scripts to deploy resources, different Terraform scripts. Use the same steps as identified in teh ARM Conversion section.

1. Convert script to different Terraform deployment modules
2. Update the README.md file with the updated deployment process

### Bugs to fix
none at this time

## Security Improvements
The solution is highly suspect and allows overly permissive policies for features. These must be improved.

### git branch
security

### Steps for Security 
1. Audit the existing architecture and identify additional security improvements. Place these as point 3 in this section if they are not listed in point 2 below.
2. Noted security improvements. 
  1. Improve security for DynamoDB permissions given to the pods. These should be limited to the tables and actions required.
  2. Improve security for S3 permissions given to the pods. These should be limted to the bucket(s) and actions required.
3. Items found during security audit


## Cost Optimization
The solution is questionable for cost management. Analyze the solution and determine any possible cost savings that can be implemented.

### git branch
cost_optimization

### Steps for Cost Optimization
1. Audit the solution and place any cost findings in point 2 below.
2. Items found during cost optimization audit

## Load Testing
This section will generate dashboards and load testing scripts for the solution, using the Python Locust framework.

### git branch
load_testing

### Steps for load testing
1. Generate dashboard to monitor pods, DynamoDB tables, S3 bucket, and ElastiCache redis instance.
2. Generate Python Locust scripts to send traffic to the solution, with targets of 100, 1000, and 10000 request per second.
3. Record and analyze the results.
