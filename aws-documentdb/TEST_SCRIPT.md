# Open Saves Test Script

This is a standardized test script for Open Saves AWS that works with both ARM64 and AMD64 architectures.

## Features

- **Architecture Detection**: Automatically detects the current architecture and configures the test accordingly
- **Standardized API Paths**: Uses the `/api/` prefix for all API endpoints
- **Redis Connectivity Test**: Tests Redis connectivity and functionality
- **Comprehensive Testing**: Tests all aspects of the Open Saves API including:
  - Store operations (create, list, get, delete)
  - Record operations (create, get, update, delete, query)
  - Blob operations (upload, download, list, delete)
  - Metadata operations (create, get, update, delete)
  - Redis caching performance

## Usage

```bash
./open-saves-test.sh http://SERVICE_URL:8080
```

Where `SERVICE_URL` is the URL of the Open Saves service.

You can also explicitly set the architecture:

```bash
ARCH=amd64 ./open-saves-test.sh http://SERVICE_URL:8080
ARCH=arm64 ./open-saves-test.sh http://SERVICE_URL:8080
```

## Architecture Support

The script automatically detects the current architecture (ARM64 or AMD64) and configures the Redis test pod accordingly. This ensures that the test pod can be scheduled on the appropriate nodes.

## API Paths

All API endpoints use the `/api/` prefix:

- `/api/stores` - List or create stores
- `/api/stores/{storeId}` - Get, update, or delete a store
- `/api/stores/{storeId}/records` - List or create records in a store
- `/api/stores/{storeId}/records/{recordId}` - Get, update, or delete a record
- `/api/stores/{storeId}/records/{recordId}/blobs` - List blobs in a record
- `/api/stores/{storeId}/records/{recordId}/blobs/{blobKey}` - Get, update, or delete a blob
- `/api/metadata/{metadataType}/{metadataId}` - Get, update, or delete metadata

## Standardization

This script has been standardized to work with both ARM64 and AMD64 architectures. It uses the same API paths (`/api/` prefix) for both architectures, ensuring consistent testing and operation across different deployments.
