package server

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
	"github.com/aws/aws-sdk-go/service/dynamodb/expression"
)

// DynamoDBStore implements the Store interface using AWS DynamoDB
type DynamoDBStore struct {
	client          *dynamodb.DynamoDB
	storesTable     string
	recordsTable    string
	metadataTable   string
}

// DynamoDBStoreItem represents a store item in DynamoDB
type DynamoDBStoreItem struct {
	StoreID   string    `json:"store_id"`
	Name      string    `json:"name"`
	CreatedAt int64     `json:"created_at"`
	UpdatedAt int64     `json:"updated_at"`
}

// DynamoDBRecordItem represents a record item in DynamoDB
type DynamoDBRecordItem struct {
	StoreID    string                 `json:"store_id"`
	RecordID   string                 `json:"record_id"`
	ConcatKey  string				  `json:"concat_key"`
	OwnerID    string                 `json:"owner_id,omitempty"`
	GameID     string                 `json:"game_id,omitempty"`	
	Tags       []string               `json:"tags,omitempty"`
	Properties map[string]interface{} `json:"properties,omitempty"`
	BlobKeys   []string               `json:"blob_keys,omitempty"`
	CreatedAt  int64                  `json:"created_at"`
	UpdatedAt  int64                  `json:"updated_at"`
}

// DynamoDBMetadataItem represents a metadata item in DynamoDB
type DynamoDBMetadataItem struct {
	MetadataType string                 `json:"metadata_type"`
	MetadataID   string                 `json:"metadata_id"`
	Data         map[string]interface{} `json:"data"`
	CreatedAt    int64                  `json:"created_at"`
	UpdatedAt    int64                  `json:"updated_at"`
}

// NewDynamoDBStore creates a new DynamoDB store
func NewDynamoDBStore(region, storesTable, recordsTable, metadataTable string) (*DynamoDBStore, error) {
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		return nil, err
	}

	return &DynamoDBStore{
		client:        dynamodb.New(sess),
		storesTable:   storesTable,
		recordsTable:  recordsTable,
		metadataTable: metadataTable,
	}, nil
}

// CreateStore creates a new store
func (s *DynamoDBStore) CreateStore(ctx context.Context, storeID, name string) error {
	now := time.Now().Unix()
	item := DynamoDBStoreItem{
		StoreID:   storeID,
		Name:      name,
		CreatedAt: now,
		UpdatedAt: now,
	}

	av, err := dynamodbattribute.MarshalMap(item)
	if err != nil {
		return fmt.Errorf("failed to marshal store item: %v", err)
	}

	_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.storesTable),
		Item:                av,
		ConditionExpression: aws.String("attribute_not_exists(store_id)"),
	})

	if err != nil {
		return fmt.Errorf("failed to put store item: %v", err)
	}

	// Create store metadata entry
	metaItem := DynamoDBMetadataItem{
		MetadataType: "store_info",
		MetadataID:   storeID,
		Data: map[string]interface{}{
			"name":       name,
			"created_at": now,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	metaAV, err := dynamodbattribute.MarshalMap(metaItem)
	if err != nil {
		log.Printf("Warning: Failed to marshal store metadata: %v", err)
		// Continue anyway, the store was created successfully
	} else {
		_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(s.metadataTable),
			Item:      metaAV,
		})
		if err != nil {
			log.Printf("Warning: Failed to put store metadata: %v", err)
			// Continue anyway, the store was created successfully
		}
	}

	return nil
}

// GetStore retrieves a store by ID
func (s *DynamoDBStore) GetStore(ctx context.Context, storeID string) (*StoreInfo, error) {
	result, err := s.client.GetItemWithContext(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.storesTable),
		Key: map[string]*dynamodb.AttributeValue{
			"store_id": {
				S: aws.String(storeID),
			},
		},
	})

	if err != nil {
		return nil, fmt.Errorf("failed to get store: %v", err)
	}

	if result.Item == nil {
		return nil, fmt.Errorf("store not found: %s", storeID)
	}

	var item DynamoDBStoreItem
	if err := dynamodbattribute.UnmarshalMap(result.Item, &item); err != nil {
		return nil, fmt.Errorf("failed to unmarshal store item: %v", err)
	}

	return &StoreInfo{
		StoreID:   item.StoreID,
		Name:      item.Name,
		CreatedAt: time.Unix(item.CreatedAt, 0),
		UpdatedAt: time.Unix(item.UpdatedAt, 0),
	}, nil
}

// ListStores returns all stores
func (s *DynamoDBStore) ListStores(ctx context.Context) ([]*StoreInfo, error) {
	// Scan the stores table
	result, err := s.client.ScanWithContext(ctx, &dynamodb.ScanInput{
		TableName: aws.String(s.storesTable),
	})

	if err != nil {
		return nil, fmt.Errorf("failed to scan stores: %v", err)
	}

	stores := make([]*StoreInfo, 0, len(result.Items))
	for _, item := range result.Items {
		var dbItem DynamoDBStoreItem
		if err := dynamodbattribute.UnmarshalMap(item, &dbItem); err != nil {
			log.Printf("Failed to unmarshal store item: %v", err)
			continue
		}

		stores = append(stores, &StoreInfo{
			StoreID:   dbItem.StoreID,
			Name:      dbItem.Name,
			CreatedAt: time.Unix(dbItem.CreatedAt, 0),
			UpdatedAt: time.Unix(dbItem.UpdatedAt, 0),
		})
	}

	return stores, nil
}

// DeleteStore deletes a store and all its records
func (s *DynamoDBStore) DeleteStore(ctx context.Context, storeID string) error {
	// First, delete the store
	_, err := s.client.DeleteItemWithContext(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.storesTable),
		Key: map[string]*dynamodb.AttributeValue{
			"store_id": {
				S: aws.String(storeID),
			},
		},
	})

	if err != nil {
		return fmt.Errorf("failed to delete store: %v", err)
	}

	// Query for all records in the store
	keyCondition := expression.Key("store_id").Equal(expression.Value(storeID))
	expr, err := expression.NewBuilder().WithKeyCondition(keyCondition).Build()
	if err != nil {
		return fmt.Errorf("failed to build expression: %v", err)
	}

	result, err := s.client.QueryWithContext(ctx, &dynamodb.QueryInput{
		TableName:                 aws.String(s.recordsTable),
		KeyConditionExpression:    expr.KeyCondition(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
	})

	if err != nil {
		return fmt.Errorf("failed to query store records: %v", err)
	}

	// Delete all records in batches of 25 (DynamoDB limit)
	for i := 0; i < len(result.Items); i += 25 {
		end := i + 25
		if end > len(result.Items) {
			end = len(result.Items)
		}

		writeRequests := make([]*dynamodb.WriteRequest, 0, end-i)
		for j := i; j < end; j++ {
			var item DynamoDBRecordItem
			if err := dynamodbattribute.UnmarshalMap(result.Items[j], &item); err != nil {
				log.Printf("Failed to unmarshal record item: %v", err)
				continue
			}

			writeRequests = append(writeRequests, &dynamodb.WriteRequest{
				DeleteRequest: &dynamodb.DeleteRequest{
					Key: map[string]*dynamodb.AttributeValue{
						"store_id": {
							S: aws.String(item.StoreID),
						},
						"record_id": {
							S: aws.String(item.RecordID),
						},
					},
				},
			})
		}

		if len(writeRequests) > 0 {
			_, err = s.client.BatchWriteItemWithContext(ctx, &dynamodb.BatchWriteItemInput{
				RequestItems: map[string][]*dynamodb.WriteRequest{
					s.recordsTable: writeRequests,
				},
			})

			if err != nil {
				return fmt.Errorf("failed to batch delete records: %v", err)
			}
		}
	}

	// Delete store metadata
	_, err = s.client.DeleteItemWithContext(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.metadataTable),
		Key: map[string]*dynamodb.AttributeValue{
			"metadata_type": {
				S: aws.String("store_info"),
			},
			"metadata_id": {
				S: aws.String(storeID),
			},
		},
	})

	if err != nil {
		log.Printf("Warning: Failed to delete store metadata: %v", err)
		// Continue anyway, the store and records were deleted successfully
	}

	return nil
}

// CreateRecord creates a new record
func (s *DynamoDBStore) CreateRecord(ctx context.Context, storeID, recordID string, record *Record) error {
	// First, check if the store exists
	_, err := s.GetStore(ctx, storeID)
	if err != nil {
		return fmt.Errorf("store not found: %s", storeID)
	}

	now := time.Now().Unix()
	// Extract OwnerID and GameID from Properties map
	var ownerID, gameID string
	if record.Properties != nil {
		if ownerIDVal, exists := record.Properties["owner_id"]; exists && ownerIDVal != nil {
			if ownerIDStr, ok := ownerIDVal.(string); ok {
				ownerID = ownerIDStr
			}
		}
		if gameIDVal, exists := record.Properties["game_id"]; exists && gameIDVal != nil {
			if gameIDStr, ok := gameIDVal.(string); ok {
				gameID = gameIDStr
			}
		}
	}

	item := DynamoDBRecordItem{
		StoreID:    storeID,
		RecordID:   recordID,
		ConcatKey:  storeID + "#" + recordID,
		OwnerID:    ownerID,
		GameID:     gameID,
		Tags:       record.Tags,
		Properties: record.Properties,
		BlobKeys:   record.BlobKeys,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	av, err := dynamodbattribute.MarshalMap(item)
	if err != nil {
		return fmt.Errorf("failed to marshal record item: %v", err)
	}

	_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
		TableName:           aws.String(s.recordsTable),
		Item:                av,
		ConditionExpression: aws.String("attribute_not_exists(store_id) AND attribute_not_exists(record_id)"),
	})

	if err != nil {
		return fmt.Errorf("failed to put record item: %v", err)
	}

	// Update store metadata with record count
	metaResult, err := s.client.GetItemWithContext(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.metadataTable),
		Key: map[string]*dynamodb.AttributeValue{
			"metadata_type": {
				S: aws.String("store_stats"),
			},
			"metadata_id": {
				S: aws.String(storeID),
			},
		},
	})

	var recordCount int64 = 1
	if err == nil && metaResult.Item != nil {
		var metaItem DynamoDBMetadataItem
		if err := dynamodbattribute.UnmarshalMap(metaResult.Item, &metaItem); err == nil {
			if count, ok := metaItem.Data["record_count"].(float64); ok {
				recordCount = int64(count) + 1
			}
		}
	}

	metaItem := DynamoDBMetadataItem{
		MetadataType: "store_stats",
		MetadataID:   storeID,
		Data: map[string]interface{}{
			"record_count": recordCount,
			"updated_at":   now,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	metaAV, err := dynamodbattribute.MarshalMap(metaItem)
	if err == nil {
		_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(s.metadataTable),
			Item:      metaAV,
		})
		if err != nil {
			log.Printf("Warning: Failed to update store stats metadata: %v", err)
			// Continue anyway, the record was created successfully
		}
	}

	return nil
}

// GetRecord retrieves a record by ID
func (s *DynamoDBStore) GetRecord(ctx context.Context, storeID, recordID string) (*Record, error) {
	result, err := s.client.GetItemWithContext(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.recordsTable),
		Key: map[string]*dynamodb.AttributeValue{
			"store_id": {
				S: aws.String(storeID),
			},
			"record_id": {
				S: aws.String(recordID),
			},
		},
	})

	if err != nil {
		return nil, fmt.Errorf("failed to get record: %v", err)
	}

	if result.Item == nil {
		return nil, fmt.Errorf("record not found: %s/%s", storeID, recordID)
	}

	var item DynamoDBRecordItem
	if err := dynamodbattribute.UnmarshalMap(result.Item, &item); err != nil {
		return nil, fmt.Errorf("failed to unmarshal record item: %v", err)
	}

	return &Record{
		StoreID:    item.StoreID,
		RecordID:   item.RecordID,
		Tags:       item.Tags,
		Properties: item.Properties,
		BlobKeys:   item.BlobKeys,
		CreatedAt:  time.Unix(item.CreatedAt, 0),
		UpdatedAt:  time.Unix(item.UpdatedAt, 0),
	}, nil
}

// QueryRecords queries records in a store
func (s *DynamoDBStore) QueryRecords(ctx context.Context, storeID string, query *Query) ([]*Record, error) {
	var input *dynamodb.QueryInput
	var err error

	// Determine query type and build appropriate query
	if query.GameID != "" {
		// Query by game_id using GameIDIndex
		input, err = s.buildGameIDQuery(storeID, query)
	} else if query.OwnerID != "" {
		// Query by owner_id using OwnerIDIndex
		input, err = s.buildOwnerIDQuery(storeID, query)
	} else {
		// No specific query - scan all records in the store
		input, err = s.buildStoreQuery(storeID, query)
	}

	if err != nil {
		return nil, fmt.Errorf("failed to build query: %v", err)
	}

	// Execute the query
	result, err := s.client.QueryWithContext(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("failed to query records: %v", err)
	}

	// Process the results
	records := make([]*Record, 0, len(result.Items))
	for _, item := range result.Items {
		var dbItem DynamoDBRecordItem
		if err := dynamodbattribute.UnmarshalMap(item, &dbItem); err != nil {
			log.Printf("Failed to unmarshal record item: %v", err)
			continue
		}
		
		records = append(records, &Record{
			StoreID:    dbItem.StoreID,
			RecordID:   dbItem.RecordID,
			OwnerID:    dbItem.OwnerID,
			GameID:     dbItem.GameID,
			Tags:       dbItem.Tags,
			Properties: dbItem.Properties,
			BlobKeys:   dbItem.BlobKeys,
			CreatedAt:  time.Unix(dbItem.CreatedAt, 0),
			UpdatedAt:  time.Unix(dbItem.UpdatedAt, 0),
		})
	}
	
	return records, nil
}

// buildGameIDQuery builds a query for the GameIDIndex
func (s *DynamoDBStore) buildGameIDQuery(storeID string, query *Query) (*dynamodb.QueryInput, error) {
	// Key condition: game_id = :game_id AND concat_key begins_with :store_prefix
	keyCondition := expression.Key("game_id").Equal(expression.Value(query.GameID)).
		And(expression.Key("concat_key").BeginsWith(storeID + "#"))

	builder := expression.NewBuilder().WithKeyCondition(keyCondition)

	// Add limit if specified
	if query.Limit > 0 {
		// Note: Limit will be applied to the query input
	}

	expr, err := builder.Build()
	if err != nil {
		return nil, err
	}

	input := &dynamodb.QueryInput{
		TableName:                 aws.String(s.recordsTable),
		IndexName:                 aws.String("GameIDIndex"),
		KeyConditionExpression:    expr.KeyCondition(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
	}

	if query.Limit > 0 {
		input.Limit = aws.Int64(int64(query.Limit))
	}

	return input, nil
}

// buildOwnerIDQuery builds a query for the OwnerIDIndex
func (s *DynamoDBStore) buildOwnerIDQuery(storeID string, query *Query) (*dynamodb.QueryInput, error) {
	// Key condition: owner_id = :owner_id AND concat_key begins_with :store_prefix
	keyCondition := expression.Key("owner_id").Equal(expression.Value(query.OwnerID)).
		And(expression.Key("concat_key").BeginsWith(storeID + "#"))

	builder := expression.NewBuilder().WithKeyCondition(keyCondition)

	expr, err := builder.Build()
	if err != nil {
		return nil, err
	}

	input := &dynamodb.QueryInput{
		TableName:                 aws.String(s.recordsTable),
		IndexName:                 aws.String("OwnerIDIndex"),
		KeyConditionExpression:    expr.KeyCondition(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
	}

	if query.Limit > 0 {
		input.Limit = aws.Int64(int64(query.Limit))
	}

	return input, nil
}

// buildStoreQuery builds a query for all records in a store (main table)
func (s *DynamoDBStore) buildStoreQuery(storeID string, query *Query) (*dynamodb.QueryInput, error) {
	// Key condition for the store ID
	keyCondition := expression.Key("store_id").Equal(expression.Value(storeID))

	builder := expression.NewBuilder().WithKeyCondition(keyCondition)

	expr, err := builder.Build()
	if err != nil {
		return nil, err
	}

	input := &dynamodb.QueryInput{
		TableName:                 aws.String(s.recordsTable),
		KeyConditionExpression:    expr.KeyCondition(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
	}

	if query.Limit > 0 {
		input.Limit = aws.Int64(int64(query.Limit))
	}

	return input, nil
}

// UpdateRecord updates an existing record
func (s *DynamoDBStore) UpdateRecord(ctx context.Context, storeID, recordID string, record *Record) error {
	now := time.Now().Unix()

	// Build update expression
	update := expression.Set(expression.Name("updated_at"), expression.Value(now))

	// Extract and update OwnerID from Properties if it exists
	if record.Properties != nil {
		if ownerIDVal, exists := record.Properties["owner_id"]; exists && ownerIDVal != nil {
			if ownerIDStr, ok := ownerIDVal.(string); ok && ownerIDStr != "" {
				update = update.Set(expression.Name("owner_id"), expression.Value(ownerIDStr))
			}
		}
	}

	if record.Tags != nil {
		update = update.Set(expression.Name("tags"), expression.Value(record.Tags))
	}

	if record.Properties != nil {
		update = update.Set(expression.Name("properties"), expression.Value(record.Properties))
	}

	if record.BlobKeys != nil {
		update = update.Set(expression.Name("blob_keys"), expression.Value(record.BlobKeys))
	}

	// Extract and update GameID from Properties if it exists
	if record.Properties != nil {
		if gameIDVal, exists := record.Properties["game_id"]; exists && gameIDVal != nil {
			if gameIDStr, ok := gameIDVal.(string); ok && gameIDStr != "" {
				update = update.Set(expression.Name("game_id"), expression.Value(gameIDStr))
			}
		}
	}


	expr, err := expression.NewBuilder().WithUpdate(update).Build()
	if err != nil {
		return fmt.Errorf("failed to build expression: %v", err)
	}

	_, err = s.client.UpdateItemWithContext(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(s.recordsTable),
		Key: map[string]*dynamodb.AttributeValue{
			"store_id": {
				S: aws.String(storeID),
			},
			"record_id": {
				S: aws.String(recordID),
			},
		},
		UpdateExpression:          expr.Update(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
		ConditionExpression:       aws.String("attribute_exists(store_id) AND attribute_exists(record_id)"),
	})

	if err != nil {
		return fmt.Errorf("failed to update record: %v", err)
	}

	return nil
}

// DeleteRecord deletes a record
func (s *DynamoDBStore) DeleteRecord(ctx context.Context, storeID, recordID string) error {
	_, err := s.client.DeleteItemWithContext(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.recordsTable),
		Key: map[string]*dynamodb.AttributeValue{
			"store_id": {
				S: aws.String(storeID),
			},
			"record_id": {
				S: aws.String(recordID),
			},
		},
	})

	if err != nil {
		return fmt.Errorf("failed to delete record: %v", err)
	}

	// Update store metadata with record count
	metaResult, err := s.client.GetItemWithContext(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.metadataTable),
		Key: map[string]*dynamodb.AttributeValue{
			"metadata_type": {
				S: aws.String("store_stats"),
			},
			"metadata_id": {
				S: aws.String(storeID),
			},
		},
	})

	if err == nil && metaResult.Item != nil {
		var metaItem DynamoDBMetadataItem
		if err := dynamodbattribute.UnmarshalMap(metaResult.Item, &metaItem); err == nil {
			if count, ok := metaItem.Data["record_count"].(float64); ok && count > 0 {
				now := time.Now().Unix()
				metaItem.Data["record_count"] = count - 1
				metaItem.Data["updated_at"] = now
				metaItem.UpdatedAt = now

				metaAV, err := dynamodbattribute.MarshalMap(metaItem)
				if err == nil {
					_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
						TableName: aws.String(s.metadataTable),
						Item:      metaAV,
					})
					if err != nil {
						log.Printf("Warning: Failed to update store stats metadata: %v", err)
						// Continue anyway, the record was deleted successfully
					}
				}
			}
		}
	}

	return nil
}

// GetMetadata retrieves metadata by type and ID
func (s *DynamoDBStore) GetMetadata(ctx context.Context, metadataType, metadataID string) (map[string]interface{}, error) {
	result, err := s.client.GetItemWithContext(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(s.metadataTable),
		Key: map[string]*dynamodb.AttributeValue{
			"metadata_type": {
				S: aws.String(metadataType),
			},
			"metadata_id": {
				S: aws.String(metadataID),
			},
		},
	})

	if err != nil {
		return nil, fmt.Errorf("failed to get metadata: %v", err)
	}

	if result.Item == nil {
		return nil, fmt.Errorf("metadata not found: %s/%s", metadataType, metadataID)
	}

	var item DynamoDBMetadataItem
	if err := dynamodbattribute.UnmarshalMap(result.Item, &item); err != nil {
		return nil, fmt.Errorf("failed to unmarshal metadata item: %v", err)
	}

	return item.Data, nil
}

// SetMetadata sets metadata by type and ID
func (s *DynamoDBStore) SetMetadata(ctx context.Context, metadataType, metadataID string, data map[string]interface{}) error {
	now := time.Now().Unix()
	item := DynamoDBMetadataItem{
		MetadataType: metadataType,
		MetadataID:   metadataID,
		Data:         data,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	av, err := dynamodbattribute.MarshalMap(item)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata item: %v", err)
	}

	_, err = s.client.PutItemWithContext(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(s.metadataTable),
		Item:      av,
	})

	if err != nil {
		return fmt.Errorf("failed to put metadata item: %v", err)
	}

	return nil
}

// DeleteMetadata deletes metadata by type and ID
func (s *DynamoDBStore) DeleteMetadata(ctx context.Context, metadataType, metadataID string) error {
	_, err := s.client.DeleteItemWithContext(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(s.metadataTable),
		Key: map[string]*dynamodb.AttributeValue{
			"metadata_type": {
				S: aws.String(metadataType),
			},
			"metadata_id": {
				S: aws.String(metadataID),
			},
		},
	})

	if err != nil {
		return fmt.Errorf("failed to delete metadata: %v", err)
	}

	return nil
}

// QueryMetadata queries metadata by type
func (s *DynamoDBStore) QueryMetadata(ctx context.Context, metadataType string) ([]map[string]interface{}, error) {
	keyCondition := expression.Key("metadata_type").Equal(expression.Value(metadataType))
	expr, err := expression.NewBuilder().WithKeyCondition(keyCondition).Build()
	if err != nil {
		return nil, fmt.Errorf("failed to build expression: %v", err)
	}

	result, err := s.client.QueryWithContext(ctx, &dynamodb.QueryInput{
		TableName:                 aws.String(s.metadataTable),
		KeyConditionExpression:    expr.KeyCondition(),
		ExpressionAttributeNames:  expr.Names(),
		ExpressionAttributeValues: expr.Values(),
	})

	if err != nil {
		return nil, fmt.Errorf("failed to query metadata: %v", err)
	}

	metadata := make([]map[string]interface{}, 0, len(result.Items))
	for _, item := range result.Items {
		var metaItem DynamoDBMetadataItem
		if err := dynamodbattribute.UnmarshalMap(item, &metaItem); err != nil {
			log.Printf("Failed to unmarshal metadata item: %v", err)
			continue
		}

		// Add metadata ID to the data
		metaItem.Data["metadata_id"] = metaItem.MetadataID
		metadata = append(metadata, metaItem.Data)
	}

	return metadata, nil
}
