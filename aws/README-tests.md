# Open Saves AWS Testing Guide

This guide explains how to use the comprehensive test suite for the Open Saves AWS adapter with multi-table DynamoDB implementation.

## Test Suite Overview

The test suite includes three types of tests:

1. **Unit Tests**: Test individual components in isolation
2. **Integration Tests**: Test the interaction between components
3. **API Tests**: Test the deployed API endpoints

All these tests can be run using the `test-client.sh` script.

## Prerequisites

- For unit tests:
  - Go 1.20+
  - AWS credentials (can be dummy values for unit tests)

- For integration tests:
  - Go 1.20+
  - Valid AWS credentials with permissions to create and delete:
    - DynamoDB tables
    - S3 buckets
    - S3 objects

- For API tests:
  - curl
  - A deployed Open Saves API endpoint

## Running Tests

### Basic Usage

```bash
# Run unit tests only
./test-client.sh --unit

# Run integration tests only
./test-client.sh --integration

# Run API tests only
./test-client.sh --api http://your-api-url

# Run all tests
./test-client.sh --all http://your-api-url
```

### Environment Variables

For integration tests, you need to set AWS credentials:

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-west-2
```

### Test Output

All test results are saved to the `test-output/` directory:

- `unit-tests.log`: Output from unit tests
- `integration-tests.log`: Output from integration tests
- `api-tests.log`: Summary of API test results

## Test Details

### Unit Tests

Unit tests verify that each component works correctly in isolation:

- Tests for DynamoDB store operations on stores, records, and metadata
- Tests for error handling and edge cases
- Tests for query functionality

### Integration Tests

Integration tests verify the interaction between components:

- Tests for the complete workflow from store creation to deletion
- Tests for blob storage with S3
- Tests for metadata operations

### API Tests

API tests verify that the deployed API endpoints work correctly:

- Tests for basic endpoints (root, health)
- Tests for store operations (create, get, list)
- Tests for record operations (create, get, update)
- Tests for blob operations (upload, download)
- Tests for metadata operations (if implemented)

## Test Resources

The tests use separate resources to avoid interfering with production data:

- Unit tests: `open-saves-stores-test`, `open-saves-records-test`, `open-saves-metadata-test`
- Integration tests: `open-saves-stores-integration`, `open-saves-records-integration`, `open-saves-metadata-integration`

## Troubleshooting

### Unit Tests Failing

- Check that Go is installed and in your PATH
- Check that AWS credentials are set (can be dummy values)
- Check the test output in `test-output/unit-tests.log`

### Integration Tests Failing

- Check that valid AWS credentials are set
- Check that the credentials have sufficient permissions
- Check the test output in `test-output/integration-tests.log`

### API Tests Failing

- Check that the API URL is correct
- Check that the API is running
- Check the test output in `test-output/api-tests.log`
- Try accessing the API endpoints manually with curl

## Extending the Tests

### Adding New Unit Tests

Add new test functions to `server/dynamodb_store_test.go` following the naming convention `TestDynamoDBStore_*`.

### Adding New Integration Tests

Add new test functions to `server/integration_test.go` following the naming convention `TestIntegration_*`.

### Adding New API Tests

Modify the `test-client.sh` script to add new API test cases.
