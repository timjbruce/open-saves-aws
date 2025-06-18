# Open Saves

This repository contains implementations of Open Saves, a cloud-based storage solution for game save data.

## Overview

Open Saves is a specialized storage system designed for game developers to store and manage game save data in the cloud. It provides a unified API for storing both structured and unstructured data, with implementations for different cloud providers.

## Implementations

### AWS Implementation

The AWS implementation of Open Saves is located in the `/aws` directory. It uses AWS services such as:
- Amazon EKS for container orchestration
- Amazon DynamoDB for metadata and small record storage
- Amazon S3 for blob storage
- Amazon ElastiCache Redis for caching

For detailed information about the AWS implementation, see the [AWS README](/aws/README.md).

### GCP Implementation

The GCP implementation of Open Saves is located in the `/gcp` directory. It uses Google Cloud Platform services such as:
- Google Kubernetes Engine for container orchestration
- Firestore for metadata and small record storage
- Cloud Storage for blob storage
- Memorystore Redis for caching

For detailed information about the GCP implementation, see the [GCP README](/gcp/README.md).

## Architecture

Open Saves follows a cloud-native architecture with the following components:

1. **API Layer**: gRPC service that exposes the Open Saves API
2. **Metadata Store**: For storing metadata about stores and records
3. **Blob Storage**: For storing large binary objects
4. **Cache Layer**: For improving performance of frequently accessed data

## Key Features

- Store and retrieve game save data
- Support for both structured data and binary blobs
- Efficient caching for improved performance
- Scalable architecture for high-traffic games
- Support for multiple cloud providers

## Contributing

Please see CONTRIBUTING.md for details on how to contribute to this project.

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.
