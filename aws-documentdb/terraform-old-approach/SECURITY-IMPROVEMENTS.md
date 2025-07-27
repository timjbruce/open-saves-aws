# Security Improvements for Open Saves AWS Implementation

This document outlines the security improvements implemented in the Terraform scripts for the Open Saves AWS deployment.

## Overview

The security improvements focus on implementing the principle of least privilege by restricting IAM permissions to only the actions and resources that are actually required by the Open Saves application.

## IAM Policy Improvements

### 1. DynamoDB Policy (`dynamodb_policy`)

**Previous Issues:**
- Missing permissions for Global Secondary Indexes (GSIs)
- Lack of detailed documentation on permission usage

**Improvements:**
- ✅ Added explicit permissions for `GameIDIndex` and `OwnerIDIndex` GSIs
- ✅ Documented each permission with its specific use case
- ✅ Restricted permissions to only required actions per table

**Permissions by Table:**

#### Stores Table
- `dynamodb:PutItem` - CreateStore
- `dynamodb:GetItem` - GetStore  
- `dynamodb:Scan` - ListStores
- `dynamodb:DeleteItem` - DeleteStore

#### Records Table (including GSI access)
- `dynamodb:PutItem` - CreateRecord
- `dynamodb:GetItem` - GetRecord
- `dynamodb:Query` - QueryRecords (main table and GSIs), DeleteStore (to find records)
- `dynamodb:UpdateItem` - UpdateRecord
- `dynamodb:DeleteItem` - DeleteRecord
- `dynamodb:BatchWriteItem` - DeleteStore (batch delete records)

**GSI Resources:**
- `arn:aws:dynamodb:region:account:table/open-saves-records/index/GameIDIndex`
- `arn:aws:dynamodb:region:account:table/open-saves-records/index/OwnerIDIndex`

#### Metadata Table
- `dynamodb:PutItem` - CreateStore, CreateRecord, DeleteRecord, SetMetadata
- `dynamodb:GetItem` - CreateRecord, DeleteRecord, GetMetadata
- `dynamodb:DeleteItem` - DeleteStore, DeleteMetadata
- `dynamodb:Query` - QueryMetadata

### 2. S3 Policy (`s3_policy`)

**Improvements:**
- ✅ Documented each permission with its specific use case
- ✅ Maintained minimal required permissions for blob operations

**Permissions:**
- `s3:HeadObject` - Check if blob exists
- `s3:GetObject` - Download blob content
- `s3:PutObject` - Upload blob content
- `s3:DeleteObject` - Delete blob
- `s3:ListObjectsV2` - List blobs for a record

**Resources:**
- Bucket-level: `arn:aws:s3:::bucket-name` (for ListObjectsV2)
- Object-level: `arn:aws:s3:::bucket-name/*` (for blob operations)

### 3. SSM Parameter Store Policy (`ssm_policy`)

**Improvements:**
- ✅ Restricted access to Open Saves specific parameter paths
- ✅ Documented permission usage

**Permissions:**
- `ssm:GetParameter` - Get individual parameter
- `ssm:GetParameters` - Get multiple parameters

**Resources:**
- `arn:aws:ssm:region:*:parameter/open-saves/*`
- `arn:aws:ssm:region:*:parameter/etc/open-saves/*`

## Security Items Addressed

### ✅ Completed
1. **Overly permissive DynamoDB permissions** - Fixed with detailed, action-specific permissions
2. **Missing GSI permissions** - Added explicit GameIDIndex and OwnerIDIndex access
3. **Overly permissive S3 permissions** - Maintained minimal required permissions with documentation
4. **Overly permissive SSM Parameter Store permissions** - Restricted to Open Saves specific paths

### ✅ Already Secure
1. **ElastiCache permissions** - No IAM permissions needed (network access only)
2. **Node group policies** - Using standard AWS managed policies appropriately

## Testing Results

All security improvements have been tested and verified:

- ✅ Query by owner_id works correctly with OwnerIDIndex
- ✅ Query by game_id works correctly with GameIDIndex  
- ✅ All CRUD operations function properly
- ✅ Blob storage operations work correctly
- ✅ Configuration retrieval from SSM works

## Implementation Notes

1. **GSI Access Critical**: The most important fix was adding GSI permissions to the DynamoDB policy. Without these, query operations would fail with AccessDeniedException.

2. **Documentation**: Each permission now includes comments explaining its specific use case in the Open Saves application.

3. **Principle of Least Privilege**: All policies follow the principle of least privilege, granting only the minimum permissions required for functionality.

4. **Resource-Specific**: Permissions are scoped to specific resources (tables, buckets, parameter paths) rather than using wildcards where possible.

## Future Considerations

1. **S3 Bucket Policy**: Consider adding bucket-level policies for additional defense in depth
2. **VPC Endpoints**: Consider using VPC endpoints for DynamoDB and S3 to keep traffic within AWS network
3. **Encryption**: Ensure all data at rest and in transit uses appropriate encryption
4. **Monitoring**: Implement CloudTrail logging for all API calls to these resources

## Deployment

These security improvements are automatically applied when running:
```bash
./deploy-step4.sh --architecture arm64
```

The policies are defined in:
`/terraform/modules/step4-compute-app/main.tf`
