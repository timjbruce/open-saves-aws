package server

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/s3"
)

const (
	integrationTestRegion        = "us-west-2"
	integrationTestStoresTable   = "open-saves-stores-integration"
	integrationTestRecordsTable  = "open-saves-records-integration"
	integrationTestMetadataTable = "open-saves-metadata-integration"
	integrationTestBucket        = "open-saves-blobs-integration"
)

// setupIntegrationTest creates the necessary resources for integration testing
func setupIntegrationTest(t *testing.T) {
	// Skip if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping integration test: AWS credentials not available")
	}

	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(integrationTestRegion),
	})
	if err != nil {
		t.Fatalf("Failed to create AWS session: %v", err)
	}

	// Create DynamoDB client
	dynamoClient := dynamodb.New(sess)

	// Create S3 client
	s3Client := s3.New(sess)

	// Create DynamoDB tables
	tables := []struct {
		name       string
		attributes []*dynamodb.AttributeDefinition
		keySchema  []*dynamodb.KeySchemaElement
	}{
		{
			name: integrationTestStoresTable,
			attributes: []*dynamodb.AttributeDefinition{
				{
					AttributeName: aws.String("store_id"),
					AttributeType: aws.String("S"),
				},
			},
			keySchema: []*dynamodb.KeySchemaElement{
				{
					AttributeName: aws.String("store_id"),
					KeyType:       aws.String("HASH"),
				},
			},
		},
		{
			name: integrationTestRecordsTable,
			attributes: []*dynamodb.AttributeDefinition{
				{
					AttributeName: aws.String("store_id"),
					AttributeType: aws.String("S"),
				},
				{
					AttributeName: aws.String("record_id"),
					AttributeType: aws.String("S"),
				},
			},
			keySchema: []*dynamodb.KeySchemaElement{
				{
					AttributeName: aws.String("store_id"),
					KeyType:       aws.String("HASH"),
				},
				{
					AttributeName: aws.String("record_id"),
					KeyType:       aws.String("RANGE"),
				},
			},
		},
		{
			name: integrationTestMetadataTable,
			attributes: []*dynamodb.AttributeDefinition{
				{
					AttributeName: aws.String("metadata_type"),
					AttributeType: aws.String("S"),
				},
				{
					AttributeName: aws.String("metadata_id"),
					AttributeType: aws.String("S"),
				},
			},
			keySchema: []*dynamodb.KeySchemaElement{
				{
					AttributeName: aws.String("metadata_type"),
					KeyType:       aws.String("HASH"),
				},
				{
					AttributeName: aws.String("metadata_id"),
					KeyType:       aws.String("RANGE"),
				},
			},
		},
	}

	for _, table := range tables {
		_, err = dynamoClient.CreateTable(&dynamodb.CreateTableInput{
			TableName:            aws.String(table.name),
			AttributeDefinitions: table.attributes,
			KeySchema:            table.keySchema,
			BillingMode:          aws.String("PAY_PER_REQUEST"),
		})
		if err != nil && !strings.Contains(err.Error(), "Table already exists") {
			t.Fatalf("Failed to create table %s: %v", table.name, err)
		}
	}

	// Wait for tables to be active
	t.Log("Waiting for tables to be active...")
	for _, table := range tables {
		err = dynamoClient.WaitUntilTableExists(&dynamodb.DescribeTableInput{
			TableName: aws.String(table.name),
		})
		if err != nil {
			t.Fatalf("Failed to wait for table %s: %v", table.name, err)
		}
	}

	// Create S3 bucket
	_, err = s3Client.CreateBucket(&s3.CreateBucketInput{
		Bucket: aws.String(integrationTestBucket),
		CreateBucketConfiguration: &s3.CreateBucketConfiguration{
			LocationConstraint: aws.String(integrationTestRegion),
		},
	})
	if err != nil && !strings.Contains(err.Error(), "BucketAlreadyOwnedByYou") {
		t.Fatalf("Failed to create S3 bucket: %v", err)
	}

	// Wait for bucket to exist
	err = s3Client.WaitUntilBucketExists(&s3.HeadBucketInput{
		Bucket: aws.String(integrationTestBucket),
	})
	if err != nil {
		t.Fatalf("Failed to wait for S3 bucket: %v", err)
	}
}

// cleanupIntegrationTest deletes the resources created for integration testing
func cleanupIntegrationTest(t *testing.T) {
	// Skip if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		return
	}

	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(integrationTestRegion),
	})
	if err != nil {
		t.Fatalf("Failed to create AWS session: %v", err)
	}

	// Create DynamoDB client
	dynamoClient := dynamodb.New(sess)

	// Create S3 client
	s3Client := s3.New(sess)

	// Delete DynamoDB tables
	tables := []string{
		integrationTestStoresTable,
		integrationTestRecordsTable,
		integrationTestMetadataTable,
	}

	for _, table := range tables {
		_, err = dynamoClient.DeleteTable(&dynamodb.DeleteTableInput{
			TableName: aws.String(table),
		})
		if err != nil {
			t.Logf("Failed to delete table %s: %v", table, err)
		}
	}

	// Delete all objects in S3 bucket
	err = deleteAllObjects(s3Client, integrationTestBucket)
	if err != nil {
		t.Logf("Failed to delete objects in S3 bucket: %v", err)
	}

	// Delete S3 bucket
	_, err = s3Client.DeleteBucket(&s3.DeleteBucketInput{
		Bucket: aws.String(integrationTestBucket),
	})
	if err != nil {
		t.Logf("Failed to delete S3 bucket: %v", err)
	}
}

// deleteAllObjects deletes all objects in an S3 bucket
func deleteAllObjects(client *s3.S3, bucket string) error {
	// List objects
	listOutput, err := client.ListObjectsV2(&s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
	})
	if err != nil {
		return err
	}

	// Delete objects
	if len(listOutput.Contents) > 0 {
		objects := make([]*s3.ObjectIdentifier, len(listOutput.Contents))
		for i, obj := range listOutput.Contents {
			objects[i] = &s3.ObjectIdentifier{
				Key: obj.Key,
			}
		}

		_, err = client.DeleteObjects(&s3.DeleteObjectsInput{
			Bucket: aws.String(bucket),
			Delete: &s3.Delete{
				Objects: objects,
			},
		})
		if err != nil {
			return err
		}
	}

	return nil
}

// TestIntegration_FullWorkflow tests the full workflow of the Open Saves system
func TestIntegration_FullWorkflow(t *testing.T) {
	// Setup integration test resources
	setupIntegrationTest(t)
	defer cleanupIntegrationTest(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(
		integrationTestRegion,
		integrationTestStoresTable,
		integrationTestRecordsTable,
		integrationTestMetadataTable,
	)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create S3 blob store
	blobStore, err := NewS3BlobStore(integrationTestRegion, integrationTestBucket)
	if err != nil {
		t.Fatalf("Failed to create S3 blob store: %v", err)
	}

	// Create context
	ctx := context.Background()

	// 1. Create a store
	storeID := fmt.Sprintf("integration-store-%d", time.Now().UnixNano())
	storeName := "Integration Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// 2. Create a record
	recordID := fmt.Sprintf("integration-record-%d", time.Now().UnixNano())
	record := &Record{
		StoreID:  storeID,
		RecordID: recordID,
		OwnerID:  "integration-owner",
		Tags:     []string{"integration", "test"},
		Properties: map[string]interface{}{
			"test_key": "test_value",
			"number":   42,
		},
		BlobKeys:  []string{},
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	err = store.CreateRecord(ctx, storeID, recordID, record)
	if err != nil {
		t.Fatalf("Failed to create record: %v", err)
	}

	// 3. Upload a blob
	blobKey := "test-blob"
	blobData := []byte("This is test blob data")
	err = blobStore.Put(ctx, storeID, recordID, blobKey, strings.NewReader(string(blobData)), int64(len(blobData)))
	if err != nil {
		t.Fatalf("Failed to upload blob: %v", err)
	}

	// 4. Update record with blob key
	record.BlobKeys = append(record.BlobKeys, blobKey)
	err = store.UpdateRecord(ctx, storeID, recordID, record)
	if err != nil {
		t.Fatalf("Failed to update record with blob key: %v", err)
	}

	// 5. Get the record
	retrievedRecord, err := store.GetRecord(ctx, storeID, recordID)
	if err != nil {
		t.Fatalf("Failed to get record: %v", err)
	}

	// Verify record data
	if retrievedRecord.StoreID != storeID {
		t.Errorf("Expected store ID %s, got %s", storeID, retrievedRecord.StoreID)
	}
	if retrievedRecord.RecordID != recordID {
		t.Errorf("Expected record ID %s, got %s", recordID, retrievedRecord.RecordID)
	}
	if len(retrievedRecord.BlobKeys) != 1 || retrievedRecord.BlobKeys[0] != blobKey {
		t.Errorf("Expected blob keys [%s], got %v", blobKey, retrievedRecord.BlobKeys)
	}

	// 6. Get the blob
	blobReader, size, err := blobStore.Get(ctx, storeID, recordID, blobKey)
	if err != nil {
		t.Fatalf("Failed to get blob: %v", err)
	}
	defer blobReader.Close()

	// Verify blob size
	if size != int64(len(blobData)) {
		t.Errorf("Expected blob size %d, got %d", len(blobData), size)
	}

	// 7. Set metadata
	metadataType := "integration_test"
	metadataID := fmt.Sprintf("integration-metadata-%d", time.Now().UnixNano())
	metadataData := map[string]interface{}{
		"test_key": "test_value",
		"store_id": storeID,
		"record_id": recordID,
	}
	err = store.SetMetadata(ctx, metadataType, metadataID, metadataData)
	if err != nil {
		t.Fatalf("Failed to set metadata: %v", err)
	}

	// 8. Get metadata
	retrievedMetadata, err := store.GetMetadata(ctx, metadataType, metadataID)
	if err != nil {
		t.Fatalf("Failed to get metadata: %v", err)
	}

	// Verify metadata
	if retrievedMetadata["test_key"] != "test_value" {
		t.Errorf("Expected metadata test_key=test_value, got %v", retrievedMetadata["test_key"])
	}

	// 9. Query records
	query := &Query{
		OwnerID: "integration-owner",
	}
	records, err := store.QueryRecords(ctx, storeID, query)
	if err != nil {
		t.Fatalf("Failed to query records: %v", err)
	}

	// Verify query results
	if len(records) != 1 {
		t.Errorf("Expected 1 record, got %d", len(records))
	}
	if len(records) > 0 && records[0].RecordID != recordID {
		t.Errorf("Expected record ID %s, got %s", recordID, records[0].RecordID)
	}

	// 10. Delete the record
	err = store.DeleteRecord(ctx, storeID, recordID)
	if err != nil {
		t.Fatalf("Failed to delete record: %v", err)
	}

	// 11. Delete the store
	err = store.DeleteStore(ctx, storeID)
	if err != nil {
		t.Fatalf("Failed to delete store: %v", err)
	}

	// 12. Delete metadata
	err = store.DeleteMetadata(ctx, metadataType, metadataID)
	if err != nil {
		t.Fatalf("Failed to delete metadata: %v", err)
	}

	// Verify record is deleted
	_, err = store.GetRecord(ctx, storeID, recordID)
	if err == nil {
		t.Errorf("Expected error when getting deleted record, got nil")
	}

	// Verify store is deleted
	_, err = store.GetStore(ctx, storeID)
	if err == nil {
		t.Errorf("Expected error when getting deleted store, got nil")
	}

	// Verify metadata is deleted
	_, err = store.GetMetadata(ctx, metadataType, metadataID)
	if err == nil {
		t.Errorf("Expected error when getting deleted metadata, got nil")
	}
}
