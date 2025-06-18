# API Path Standardization

This document describes the standardization of API paths between the ARM64 and AMD64 implementations of Open Saves AWS.

## API Path Standard

All API endpoints use the `/api/` prefix:

- `/api/stores` - List or create stores
- `/api/stores/{storeId}` - Get, update, or delete a store
- `/api/stores/{storeId}/records` - List or create records in a store
- `/api/stores/{storeId}/records/{recordId}` - Get, update, or delete a record
- `/api/stores/{storeId}/records/{recordId}/blobs` - List blobs in a record
- `/api/stores/{storeId}/records/{recordId}/blobs/{blobKey}` - Get, update, or delete a blob
- `/api/metadata/{metadataType}/{metadataId}` - Get, update, or delete metadata

## Implementation Notes

1. Both ARM64 and AMD64 implementations use the same API paths with the `/api/` prefix.
2. The test script has been standardized to use the `/api/` prefix for all API calls.
3. The Redis test pod has been updated to use the correct architecture selector based on the deployment.

## Testing

Use the standardized test script `open-saves-test-standardized.sh` which works with both ARM64 and AMD64 deployments.
