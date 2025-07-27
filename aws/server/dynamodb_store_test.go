package server

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
)

const (
	testRegion        = "us-west-2"
	testStoresTable   = "open-saves-stores-test"
	testRecordsTable  = "open-saves-records-test"
	testMetadataTable = "open-saves-metadata-test"
)

// setupTestTables creates the test tables in DynamoDB
func setupTestTables(t *testing.T) {
	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(testRegion),
	})
	if err != nil {
		t.Fatalf("Failed to create AWS session: %v", err)
	}

	// Create DynamoDB client
	client := dynamodb.New(sess)

	// Create stores table
	_, err = client.CreateTable(&dynamodb.CreateTableInput{
		TableName: aws.String(testStoresTable),
		AttributeDefinitions: []*dynamodb.AttributeDefinition{
			{
				AttributeName: aws.String("store_id"),
				AttributeType: aws.String("S"),
			},
		},
		KeySchema: []*dynamodb.KeySchemaElement{
			{
				AttributeName: aws.String("store_id"),
				KeyType:       aws.String("HASH"),
			},
		},
		BillingMode: aws.String("PAY_PER_REQUEST"),
	})
	if err != nil {
		t.Logf("Error creating stores table (may already exist): %v", err)
	}

	// Create records table
	_, err = client.CreateTable(&dynamodb.CreateTableInput{
		TableName: aws.String(testRecordsTable),
		AttributeDefinitions: []*dynamodb.AttributeDefinition{
			{
				AttributeName: aws.String("store_id"),
				AttributeType: aws.String("S"),
			},
			{
				AttributeName: aws.String("record_id"),
				AttributeType: aws.String("S"),
			},
		},
		KeySchema: []*dynamodb.KeySchemaElement{
			{
				AttributeName: aws.String("store_id"),
				KeyType:       aws.String("HASH"),
			},
			{
				AttributeName: aws.String("record_id"),
				KeyType:       aws.String("RANGE"),
			},
		},
		BillingMode: aws.String("PAY_PER_REQUEST"),
	})
	if err != nil {
		t.Logf("Error creating records table (may already exist): %v", err)
	}

	// Create metadata table
	_, err = client.CreateTable(&dynamodb.CreateTableInput{
		TableName: aws.String(testMetadataTable),
		AttributeDefinitions: []*dynamodb.AttributeDefinition{
			{
				AttributeName: aws.String("metadata_type"),
				AttributeType: aws.String("S"),
			},
			{
				AttributeName: aws.String("metadata_id"),
				AttributeType: aws.String("S"),
			},
		},
		KeySchema: []*dynamodb.KeySchemaElement{
			{
				AttributeName: aws.String("metadata_type"),
				KeyType:       aws.String("HASH"),
			},
			{
				AttributeName: aws.String("metadata_id"),
				KeyType:       aws.String("RANGE"),
			},
		},
		BillingMode: aws.String("PAY_PER_REQUEST"),
	})
	if err != nil {
		t.Logf("Error creating metadata table (may already exist): %v", err)
	}

	// Wait for tables to be active
	t.Log("Waiting for tables to be active...")
	for _, tableName := range []string{testStoresTable, testRecordsTable, testMetadataTable} {
		err = client.WaitUntilTableExists(&dynamodb.DescribeTableInput{
			TableName: aws.String(tableName),
		})
		if err != nil {
			t.Fatalf("Failed to wait for table %s: %v", tableName, err)
		}
	}
}

// cleanupTestTables deletes the test tables from DynamoDB
func cleanupTestTables(t *testing.T) {
	// Create AWS session
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(testRegion),
	})
	if err != nil {
		t.Fatalf("Failed to create AWS session: %v", err)
	}

	// Create DynamoDB client
	client := dynamodb.New(sess)

	// Delete tables
	for _, tableName := range []string{testStoresTable, testRecordsTable, testMetadataTable} {
		_, err = client.DeleteTable(&dynamodb.DeleteTableInput{
			TableName: aws.String(tableName),
		})
		if err != nil {
			t.Logf("Error deleting table %s: %v", tableName, err)
		}
	}
}

// TestMain is the entry point for testing
func TestMain(m *testing.M) {
	// Skip tests if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		fmt.Println("Skipping DynamoDB tests: AWS credentials not available")
		os.Exit(0)
	}

	// Run tests
	code := m.Run()
	os.Exit(code)
}

// TestDynamoDBStore_CreateStore tests creating a store
func TestDynamoDBStore_CreateStore(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Get the store
	storeInfo, err := store.GetStore(ctx, storeID)
	if err != nil {
		t.Fatalf("Failed to get store: %v", err)
	}

	// Verify store data
	if storeInfo.StoreID != storeID {
		t.Errorf("Expected store ID %s, got %s", storeID, storeInfo.StoreID)
	}
	if storeInfo.Name != storeName {
		t.Errorf("Expected store name %s, got %s", storeName, storeInfo.Name)
	}

	// Verify store metadata
	metadata, err := store.GetMetadata(ctx, "store_info", storeID)
	if err != nil {
		t.Logf("Note: Store metadata not found (this is optional): %v", err)
	} else {
		if metadata["name"] != storeName {
			t.Errorf("Expected metadata name %s, got %v", storeName, metadata["name"])
		}
	}
}

// TestDynamoDBStore_ListStores tests listing stores
func TestDynamoDBStore_ListStores(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create some stores
	ctx := context.Background()
	storeIDs := []string{}
	for i := 0; i < 3; i++ {
		storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano()+int64(i))
		storeName := fmt.Sprintf("Test Store %d", i)
		err = store.CreateStore(ctx, storeID, storeName)
		if err != nil {
			t.Fatalf("Failed to create store: %v", err)
		}
		storeIDs = append(storeIDs, storeID)
	}

	// List stores
	stores, err := store.ListStores(ctx)
	if err != nil {
		t.Fatalf("Failed to list stores: %v", err)
	}

	// Verify that all created stores are in the list
	found := make(map[string]bool)
	for _, s := range stores {
		for _, id := range storeIDs {
			if s.StoreID == id {
				found[id] = true
			}
		}
	}

	for _, id := range storeIDs {
		if !found[id] {
			t.Errorf("Store %s not found in list", id)
		}
	}
}

// TestDynamoDBStore_DeleteStore tests deleting a store
func TestDynamoDBStore_DeleteStore(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Delete the store
	err = store.DeleteStore(ctx, storeID)
	if err != nil {
		t.Fatalf("Failed to delete store: %v", err)
	}

	// Try to get the store (should fail)
	_, err = store.GetStore(ctx, storeID)
	if err == nil {
		t.Errorf("Expected error when getting deleted store, got nil")
	}
}

// TestDynamoDBStore_CreateRecord tests creating a record
func TestDynamoDBStore_CreateRecord(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Create a record
	recordID := fmt.Sprintf("test-record-%d", time.Now().UnixNano())
	record := &Record{
		StoreID:    storeID,
		RecordID:   recordID,
		OwnerID:    "test-owner",
		Tags:       []string{"test", "record"},
		Properties: map[string]interface{}{"key": "value"},
		BlobKeys:   []string{},
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	err = store.CreateRecord(ctx, storeID, recordID, record)
	if err != nil {
		t.Fatalf("Failed to create record: %v", err)
	}

	// Get the record
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
	if retrievedRecord.OwnerID != record.OwnerID {
		t.Errorf("Expected owner ID %s, got %s", record.OwnerID, retrievedRecord.OwnerID)
	}
	if len(retrievedRecord.Tags) != len(record.Tags) {
		t.Errorf("Expected %d tags, got %d", len(record.Tags), len(retrievedRecord.Tags))
	}
	if val, ok := retrievedRecord.Properties["key"]; !ok || val != "value" {
		t.Errorf("Expected property key=value, got %v", retrievedRecord.Properties)
	}
}

// TestDynamoDBStore_QueryRecords tests querying records
func TestDynamoDBStore_QueryRecords(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Create records with different owners
	ownerIDs := []string{"owner1", "owner2", "owner1"}
	recordIDs := []string{}
	for i, ownerID := range ownerIDs {
		recordID := fmt.Sprintf("test-record-%d", time.Now().UnixNano()+int64(i))
		record := &Record{
			StoreID:    storeID,
			RecordID:   recordID,
			OwnerID:    ownerID,
			Tags:       []string{"test", "record"},
			Properties: map[string]interface{}{"index": i},
			BlobKeys:   []string{},
			CreatedAt:  time.Now(),
			UpdatedAt:  time.Now(),
		}
		err = store.CreateRecord(ctx, storeID, recordID, record)
		if err != nil {
			t.Fatalf("Failed to create record: %v", err)
		}
		recordIDs = append(recordIDs, recordID)
	}

	// Query records by owner
	query := &Query{
		OwnerID: "owner1",
	}
	records, err := store.QueryRecords(ctx, storeID, query)
	if err != nil {
		t.Fatalf("Failed to query records: %v", err)
	}

	// Verify that only owner1's records are returned
	if len(records) != 2 {
		t.Errorf("Expected 2 records, got %d", len(records))
	}
	for _, record := range records {
		if record.OwnerID != "owner1" {
			t.Errorf("Expected owner ID owner1, got %s", record.OwnerID)
		}
	}

	// Query with limit
	query = &Query{
		Limit: 1,
	}
	records, err = store.QueryRecords(ctx, storeID, query)
	if err != nil {
		t.Fatalf("Failed to query records with limit: %v", err)
	}

	// Verify that only one record is returned
	if len(records) != 1 {
		t.Errorf("Expected 1 record, got %d", len(records))
	}
}

// TestDynamoDBStore_UpdateRecord tests updating a record
func TestDynamoDBStore_UpdateRecord(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Create a record
	recordID := fmt.Sprintf("test-record-%d", time.Now().UnixNano())
	record := &Record{
		StoreID:    storeID,
		RecordID:   recordID,
		OwnerID:    "test-owner",
		Tags:       []string{"test", "record"},
		Properties: map[string]interface{}{"key": "value"},
		BlobKeys:   []string{},
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	err = store.CreateRecord(ctx, storeID, recordID, record)
	if err != nil {
		t.Fatalf("Failed to create record: %v", err)
	}

	// Update the record
	updatedRecord := &Record{
		StoreID:    storeID,
		RecordID:   recordID,
		OwnerID:    "new-owner",
		Tags:       []string{"updated", "record"},
		Properties: map[string]interface{}{"key": "new-value"},
		BlobKeys:   []string{"blob1"},
		UpdatedAt:  time.Now(),
	}
	err = store.UpdateRecord(ctx, storeID, recordID, updatedRecord)
	if err != nil {
		t.Fatalf("Failed to update record: %v", err)
	}

	// Get the updated record
	retrievedRecord, err := store.GetRecord(ctx, storeID, recordID)
	if err != nil {
		t.Fatalf("Failed to get updated record: %v", err)
	}

	// Verify updated record data
	if retrievedRecord.OwnerID != "new-owner" {
		t.Errorf("Expected owner ID new-owner, got %s", retrievedRecord.OwnerID)
	}
	if len(retrievedRecord.Tags) != 2 || retrievedRecord.Tags[0] != "updated" {
		t.Errorf("Expected updated tags, got %v", retrievedRecord.Tags)
	}
	if val, ok := retrievedRecord.Properties["key"]; !ok || val != "new-value" {
		t.Errorf("Expected property key=new-value, got %v", retrievedRecord.Properties)
	}
	if len(retrievedRecord.BlobKeys) != 1 || retrievedRecord.BlobKeys[0] != "blob1" {
		t.Errorf("Expected blob keys [blob1], got %v", retrievedRecord.BlobKeys)
	}
}

// TestDynamoDBStore_DeleteRecord tests deleting a record
func TestDynamoDBStore_DeleteRecord(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Create a store
	ctx := context.Background()
	storeID := fmt.Sprintf("test-store-%d", time.Now().UnixNano())
	storeName := "Test Store"
	err = store.CreateStore(ctx, storeID, storeName)
	if err != nil {
		t.Fatalf("Failed to create store: %v", err)
	}

	// Create a record
	recordID := fmt.Sprintf("test-record-%d", time.Now().UnixNano())
	record := &Record{
		StoreID:    storeID,
		RecordID:   recordID,
		OwnerID:    "test-owner",
		Tags:       []string{"test", "record"},
		Properties: map[string]interface{}{"key": "value"},
		BlobKeys:   []string{},
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}
	err = store.CreateRecord(ctx, storeID, recordID, record)
	if err != nil {
		t.Fatalf("Failed to create record: %v", err)
	}

	// Delete the record
	err = store.DeleteRecord(ctx, storeID, recordID)
	if err != nil {
		t.Fatalf("Failed to delete record: %v", err)
	}

	// Try to get the record (should fail)
	_, err = store.GetRecord(ctx, storeID, recordID)
	if err == nil {
		t.Errorf("Expected error when getting deleted record, got nil")
	}
}

// TestDynamoDBStore_Metadata tests metadata operations
func TestDynamoDBStore_Metadata(t *testing.T) {
	// Skip test if AWS credentials are not available
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		t.Skip("Skipping test: AWS credentials not available")
	}

	// Setup test tables
	setupTestTables(t)
	defer cleanupTestTables(t)

	// Create DynamoDB store
	store, err := NewDynamoDBStore(testRegion, testStoresTable, testRecordsTable, testMetadataTable)
	if err != nil {
		t.Fatalf("Failed to create DynamoDB store: %v", err)
	}

	// Set metadata
	ctx := context.Background()
	metadataType := "test_type"
	metadataID := fmt.Sprintf("test-id-%d", time.Now().UnixNano())
	metadataData := map[string]interface{}{
		"string_value": "test",
		"int_value":    42,
		"bool_value":   true,
		"nested": map[string]interface{}{
			"key": "value",
		},
	}
	err = store.SetMetadata(ctx, metadataType, metadataID, metadataData)
	if err != nil {
		t.Fatalf("Failed to set metadata: %v", err)
	}

	// Get metadata
	retrievedData, err := store.GetMetadata(ctx, metadataType, metadataID)
	if err != nil {
		t.Fatalf("Failed to get metadata: %v", err)
	}

	// Verify metadata
	if retrievedData["string_value"] != "test" {
		t.Errorf("Expected string_value=test, got %v", retrievedData["string_value"])
	}
	if retrievedData["int_value"] != float64(42) { // JSON numbers are float64 in Go
		t.Errorf("Expected int_value=42, got %v", retrievedData["int_value"])
	}
	if retrievedData["bool_value"] != true {
		t.Errorf("Expected bool_value=true, got %v", retrievedData["bool_value"])
	}

	// Query metadata
	metadataList, err := store.QueryMetadata(ctx, metadataType)
	if err != nil {
		t.Fatalf("Failed to query metadata: %v", err)
	}

	// Verify metadata list
	if len(metadataList) < 1 {
		t.Errorf("Expected at least 1 metadata item, got %d", len(metadataList))
	}
	found := false
	for _, item := range metadataList {
		if item["metadata_id"] == metadataID {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("Metadata item with ID %s not found in query results", metadataID)
	}

	// Delete metadata
	err = store.DeleteMetadata(ctx, metadataType, metadataID)
	if err != nil {
		t.Fatalf("Failed to delete metadata: %v", err)
	}

	// Try to get the deleted metadata (should fail)
	_, err = store.GetMetadata(ctx, metadataType, metadataID)
	if err == nil {
		t.Errorf("Expected error when getting deleted metadata, got nil")
	}
}
