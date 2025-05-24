# Open Saves AWS Adapter

This is an AWS implementation of the [Open Saves](https://github.com/googleforgames/open-saves) API, providing a cloud-native storage system for game developers using AWS services.

## Overview

Open Saves AWS Adapter provides a unified, well-defined gRPC endpoint for all operations for metadata, structured, and unstructured objects, leveraging AWS services:

- **DynamoDB**: For storing metadata, stores, and records
- **S3**: For blob storage
- **ElastiCache Redis**: For caching frequently accessed data

## Architecture

```
                                                  ┌───────────────────┐
                                                  │                   │
                                                  │  Game Clients     │
                                                  │                   │
                                                  └─────────┬─────────┘
                                                            │
                                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│                               AWS Cloud                                         │
│                                                                                 │
│  ┌─────────────────────┐          ┌─────────────────────┐                       │
│  │                     │          │                     │                       │
│  │   Load Balancer     │◄────────►│   EKS Cluster       │                       │
│  │                     │          │                     │                       │
│  └─────────────────────┘          └──────────┬──────────┘                       │
│                                              │                                  │
│                                              │                                  │
│                                              ▼                                  │
│  ┌─────────────────────┐          ┌─────────────────────┐                       │
│  │                     │          │                     │                       │
│  │   ElastiCache       │◄────────►│   Open Saves        │                       │
│  │   Redis Cluster     │          │   Server Pods       │                       │
│  │                     │          │                     │                       │
│  └─────────────────────┘          └──────────┬──────────┘                       │
│                                              │                                  │
│                                              │                                  │
│                                              ▼                                  │
│  ┌─────────────────────┐          ┌─────────────────────┐    ┌─────────────────┐│
│  │                     │          │                     │    │                 ││
│  │   DynamoDB Tables   │◄────────►│   AWS SDK           │    │                 ││
│  │   - Stores          │          │                     │    │                 ││
│  │   - Records         │          │                     │    │   S3 Bucket     ││
│  │   - Metadata        │          │                     │◄───►│   (Blobs)      ││
│  │                     │          │                     │    │                 ││
│  └─────────────────────┘          └─────────────────────┘    │                 ││
│                                                              └─────────────────┘│
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│               │     │               │     │               │
│  Game Client  │────►│  Open Saves   │────►│   DynamoDB    │
│               │     │    Server     │     │   (Metadata)  │
└───────────────┘     └───────┬───────┘     └───────────────┘
                              │
                              │
                  ┌───────────┴───────────┐
                  │                       │
                  ▼                       ▼
         ┌─────────────────┐     ┌─────────────────┐
         │                 │     │                 │
         │  ElastiCache    │     │  S3 Bucket      │
         │  Redis (Cache)  │     │  (Blob Storage) │
         │                 │     │                 │
         └─────────────────┘     └─────────────────┘
```

### Request Flow Example

1. **Store/Record Access**:
   ```
   Client Request → Open Saves Server → Redis Cache (if available) → DynamoDB → Response
   ```

2. **Blob Storage**:
   ```
   Client Request → Open Saves Server → S3 Bucket → Response
   ```

3. **Cache Update**:
   ```
   DynamoDB Data → Open Saves Server → Redis Cache
   ```

The Open Saves AWS Adapter uses a multi-table DynamoDB approach:

1. **Stores Table**: Stores metadata about stores
2. **Records Table**: Stores record data with a composite key (store_id, record_id)
3. **Metadata Table**: Stores system metadata

Blobs are stored in S3, with keys formatted as `{store_id}/{record_id}/{blob_key}`.

Redis is used for caching frequently accessed data, improving performance for repeated operations.

## Deployment

### Prerequisites

- AWS CLI configured with appropriate permissions
- kubectl installed
- Docker installed
- Go 1.20 or later installed

### Deployment Steps

1. Clone this repository
2. Run the deployment script:

```bash
./deploy-all.sh
```

This script will:
- Build the application
- Create a Docker image
- Push the image to ECR
- Create DynamoDB tables
- Create an S3 bucket
- Create an EKS cluster
- Create an ElastiCache Redis cluster
- Deploy the application to EKS

## Testing

To test the deployment, run:

```bash
./open-saves-test.sh http://<service-url>
```

Replace `<service-url>` with the URL of your deployed service.

The test script will verify:
- Basic functionality (health check, store operations, record operations)
- Redis caching performance
- Query operations
- Update and delete operations
- Blob operations
- Metadata operations

## API Reference

### Stores

- `GET /api/stores`: List all stores
- `POST /api/stores`: Create a store
- `GET /api/stores/{store_id}`: Get a store
- `DELETE /api/stores/{store_id}`: Delete a store

### Records

- `GET /api/stores/{store_id}/records`: List records in a store
- `POST /api/stores/{store_id}/records`: Create a record
- `GET /api/stores/{store_id}/records/{record_id}`: Get a record
- `PUT /api/stores/{store_id}/records/{record_id}`: Update a record
- `DELETE /api/stores/{store_id}/records/{record_id}`: Delete a record

### Blobs

- `GET /api/stores/{store_id}/records/{record_id}/blobs`: List blobs in a record
- `GET /api/stores/{store_id}/records/{record_id}/blobs/{blob_key}`: Get a blob
- `PUT /api/stores/{store_id}/records/{record_id}/blobs/{blob_key}`: Upload a blob
- `DELETE /api/stores/{store_id}/records/{record_id}/blobs/{blob_key}`: Delete a blob

### Metadata

- `GET /api/metadata/{metadata_type}/{metadata_id}`: Get metadata
- `POST /api/metadata/{metadata_type}/{metadata_id}`: Create or update metadata
- `DELETE /api/metadata/{metadata_type}/{metadata_id}`: Delete metadata

## License

Apache 2.0
