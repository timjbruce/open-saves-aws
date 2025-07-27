package server

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// DocumentDBStore implements the Store interface using AWS DocumentDB
type DocumentDBStore struct {
	client     *mongo.Client
	database   *mongo.Database
	stores     *mongo.Collection
	records    *mongo.Collection
	metadata   *mongo.Collection
}

// DocumentDBStoreItem represents a store document in DocumentDB
type DocumentDBStoreItem struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	StoreID   string            `bson:"store_id"`
	Name      string            `bson:"name"`
	CreatedAt int64             `bson:"created_at"`
	UpdatedAt int64             `bson:"updated_at"`
}

// DocumentDBRecordItem represents a record document in DocumentDB
type DocumentDBRecordItem struct {
	ID         primitive.ObjectID     `bson:"_id,omitempty"`
	StoreID    string                 `bson:"store_id"`
	RecordID   string                 `bson:"record_id"`
	ConcatKey  string                 `bson:"concat_key"`
	OwnerID    string                 `bson:"owner_id,omitempty"`
	GameID     string                 `bson:"game_id,omitempty"`
	Tags       []string               `bson:"tags,omitempty"`
	Properties map[string]interface{} `bson:"properties,omitempty"`
	BlobKeys   []string               `bson:"blob_keys,omitempty"`
	CreatedAt  int64                  `bson:"created_at"`
	UpdatedAt  int64                  `bson:"updated_at"`
}

// DocumentDBMetadataItem represents a metadata document in DocumentDB
type DocumentDBMetadataItem struct {
	ID           primitive.ObjectID     `bson:"_id,omitempty"`
	MetadataType string                 `bson:"metadata_type"`
	MetadataID   string                 `bson:"metadata_id"`
	Data         map[string]interface{} `bson:"data"`
	CreatedAt    int64                  `bson:"created_at"`
	UpdatedAt    int64                  `bson:"updated_at"`
}

// NewDocumentDBStore creates a new DocumentDB store
func NewDocumentDBStore(connectionString, databaseName string) (*DocumentDBStore, error) {
	// Set client options
	clientOptions := options.Client().ApplyURI(connectionString)
	
	// Create a new client and connect to the server
	client, err := mongo.Connect(context.TODO(), clientOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to DocumentDB: %v", err)
	}

	// Ping the database to verify connection
	err = client.Ping(context.TODO(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to ping DocumentDB: %v", err)
	}

	log.Println("Connected to DocumentDB!")

	database := client.Database(databaseName)
	
	return &DocumentDBStore{
		client:   client,
		database: database,
		stores:   database.Collection("stores"),
		records:  database.Collection("records"),
		metadata: database.Collection("metadata"),
	}, nil
}

// CreateStore creates a new store
func (s *DocumentDBStore) CreateStore(ctx context.Context, storeID, name string) error {
	now := time.Now().Unix()
	
	// Check if store already exists
	count, err := s.stores.CountDocuments(ctx, bson.M{"store_id": storeID})
	if err != nil {
		return fmt.Errorf("failed to check store existence: %v", err)
	}
	if count > 0 {
		return fmt.Errorf("store with ID %s already exists", storeID)
	}

	// Create store document
	storeItem := DocumentDBStoreItem{
		StoreID:   storeID,
		Name:      name,
		CreatedAt: now,
		UpdatedAt: now,
	}

	_, err = s.stores.InsertOne(ctx, storeItem)
	if err != nil {
		return fmt.Errorf("failed to insert store: %v", err)
	}

	// Create store metadata entry
	metaItem := DocumentDBMetadataItem{
		MetadataType: "store_info",
		MetadataID:   storeID,
		Data: map[string]interface{}{
			"name":       name,
			"store_id":   storeID,
			"created_at": now,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	_, err = s.metadata.InsertOne(ctx, metaItem)
	if err != nil {
		return fmt.Errorf("failed to insert store metadata: %v", err)
	}

	return nil
}

// GetStore retrieves a store by ID
func (s *DocumentDBStore) GetStore(ctx context.Context, storeID string) (*Store, error) {
	var item DocumentDBStoreItem
	err := s.stores.FindOne(ctx, bson.M{"store_id": storeID}).Decode(&item)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("store not found: %s", storeID)
		}
		return nil, fmt.Errorf("failed to get store: %v", err)
	}

	return &Store{
		StoreID:   item.StoreID,
		Name:      item.Name,
		CreatedAt: item.CreatedAt,
		UpdatedAt: item.UpdatedAt,
	}, nil
}

// ListStores lists all stores
func (s *DocumentDBStore) ListStores(ctx context.Context) ([]*Store, error) {
	cursor, err := s.stores.Find(ctx, bson.M{})
	if err != nil {
		return nil, fmt.Errorf("failed to list stores: %v", err)
	}
	defer cursor.Close(ctx)

	var stores []*Store
	for cursor.Next(ctx) {
		var item DocumentDBStoreItem
		if err := cursor.Decode(&item); err != nil {
			return nil, fmt.Errorf("failed to decode store: %v", err)
		}

		stores = append(stores, &Store{
			StoreID:   item.StoreID,
			Name:      item.Name,
			CreatedAt: item.CreatedAt,
			UpdatedAt: item.UpdatedAt,
		})
	}

	if err := cursor.Err(); err != nil {
		return nil, fmt.Errorf("cursor error: %v", err)
	}

	return stores, nil
}

// DeleteStore deletes a store and all its records
func (s *DocumentDBStore) DeleteStore(ctx context.Context, storeID string) error {
	// Start a session for transaction
	session, err := s.client.StartSession()
	if err != nil {
		return fmt.Errorf("failed to start session: %v", err)
	}
	defer session.EndSession(ctx)

	// Execute transaction
	_, err = session.WithTransaction(ctx, func(sc mongo.SessionContext) (interface{}, error) {
		// Delete all records for this store
		_, err := s.records.DeleteMany(sc, bson.M{"store_id": storeID})
		if err != nil {
			return nil, fmt.Errorf("failed to delete records: %v", err)
		}

		// Delete store metadata
		_, err = s.metadata.DeleteMany(sc, bson.M{"metadata_id": storeID})
		if err != nil {
			return nil, fmt.Errorf("failed to delete store metadata: %v", err)
		}

		// Delete the store itself
		result, err := s.stores.DeleteOne(sc, bson.M{"store_id": storeID})
		if err != nil {
			return nil, fmt.Errorf("failed to delete store: %v", err)
		}

		if result.DeletedCount == 0 {
			return nil, fmt.Errorf("store not found: %s", storeID)
		}

		return nil, nil
	})

	return err
}

// CreateRecord creates a new record
func (s *DocumentDBStore) CreateRecord(ctx context.Context, storeID, recordID, ownerID, gameID string, tags []string, properties map[string]interface{}, blobKeys []string) error {
	now := time.Now().Unix()
	concatKey := fmt.Sprintf("%s#%s", storeID, recordID)

	// Check if record already exists
	count, err := s.records.CountDocuments(ctx, bson.M{"concat_key": concatKey})
	if err != nil {
		return fmt.Errorf("failed to check record existence: %v", err)
	}
	if count > 0 {
		return fmt.Errorf("record with ID %s already exists in store %s", recordID, storeID)
	}

	// Create record document
	recordItem := DocumentDBRecordItem{
		StoreID:    storeID,
		RecordID:   recordID,
		ConcatKey:  concatKey,
		OwnerID:    ownerID,
		GameID:     gameID,
		Tags:       tags,
		Properties: properties,
		BlobKeys:   blobKeys,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	_, err = s.records.InsertOne(ctx, recordItem)
	if err != nil {
		return fmt.Errorf("failed to insert record: %v", err)
	}

	// Create record metadata entry
	metaItem := DocumentDBMetadataItem{
		MetadataType: "record_info",
		MetadataID:   concatKey,
		Data: map[string]interface{}{
			"store_id":   storeID,
			"record_id":  recordID,
			"owner_id":   ownerID,
			"game_id":    gameID,
			"tags":       tags,
			"created_at": now,
		},
		CreatedAt: now,
		UpdatedAt: now,
	}

	_, err = s.metadata.InsertOne(ctx, metaItem)
	if err != nil {
		return fmt.Errorf("failed to insert record metadata: %v", err)
	}

	return nil
}

// GetRecord retrieves a record by store ID and record ID
func (s *DocumentDBStore) GetRecord(ctx context.Context, storeID, recordID string) (*Record, error) {
	concatKey := fmt.Sprintf("%s#%s", storeID, recordID)
	
	var item DocumentDBRecordItem
	err := s.records.FindOne(ctx, bson.M{"concat_key": concatKey}).Decode(&item)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("record not found: %s in store %s", recordID, storeID)
		}
		return nil, fmt.Errorf("failed to get record: %v", err)
	}

	return &Record{
		StoreID:    item.StoreID,
		RecordID:   item.RecordID,
		OwnerID:    item.OwnerID,
		GameID:     item.GameID,
		Tags:       item.Tags,
		Properties: item.Properties,
		BlobKeys:   item.BlobKeys,
		CreatedAt:  item.CreatedAt,
		UpdatedAt:  item.UpdatedAt,
	}, nil
}

// UpdateRecord updates an existing record
func (s *DocumentDBStore) UpdateRecord(ctx context.Context, storeID, recordID string, tags []string, properties map[string]interface{}, blobKeys []string) error {
	now := time.Now().Unix()
	concatKey := fmt.Sprintf("%s#%s", storeID, recordID)

	update := bson.M{
		"$set": bson.M{
			"tags":       tags,
			"properties": properties,
			"blob_keys":  blobKeys,
			"updated_at": now,
		},
	}

	result, err := s.records.UpdateOne(ctx, bson.M{"concat_key": concatKey}, update)
	if err != nil {
		return fmt.Errorf("failed to update record: %v", err)
	}

	if result.MatchedCount == 0 {
		return fmt.Errorf("record not found: %s in store %s", recordID, storeID)
	}

	return nil
}

// DeleteRecord deletes a record
func (s *DocumentDBStore) DeleteRecord(ctx context.Context, storeID, recordID string) error {
	concatKey := fmt.Sprintf("%s#%s", storeID, recordID)

	// Start a session for transaction
	session, err := s.client.StartSession()
	if err != nil {
		return fmt.Errorf("failed to start session: %v", err)
	}
	defer session.EndSession(ctx)

	// Execute transaction
	_, err = session.WithTransaction(ctx, func(sc mongo.SessionContext) (interface{}, error) {
		// Delete record metadata
		_, err := s.metadata.DeleteMany(sc, bson.M{"metadata_id": concatKey})
		if err != nil {
			return nil, fmt.Errorf("failed to delete record metadata: %v", err)
		}

		// Delete the record itself
		result, err := s.records.DeleteOne(sc, bson.M{"concat_key": concatKey})
		if err != nil {
			return nil, fmt.Errorf("failed to delete record: %v", err)
		}

		if result.DeletedCount == 0 {
			return nil, fmt.Errorf("record not found: %s in store %s", recordID, storeID)
		}

		return nil, nil
	})

	return err
}

// QueryRecords queries records with filters
func (s *DocumentDBStore) QueryRecords(ctx context.Context, storeID string, ownerID, gameID string, tags []string, limit int32) ([]*Record, error) {
	filter := bson.M{"store_id": storeID}

	if ownerID != "" {
		filter["owner_id"] = ownerID
	}

	if gameID != "" {
		filter["game_id"] = gameID
	}

	if len(tags) > 0 {
		filter["tags"] = bson.M{"$in": tags}
	}

	opts := options.Find()
	if limit > 0 {
		opts.SetLimit(int64(limit))
	}
	opts.SetSort(bson.M{"created_at": -1}) // Sort by creation time, newest first

	cursor, err := s.records.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query records: %v", err)
	}
	defer cursor.Close(ctx)

	var records []*Record
	for cursor.Next(ctx) {
		var item DocumentDBRecordItem
		if err := cursor.Decode(&item); err != nil {
			return nil, fmt.Errorf("failed to decode record: %v", err)
		}

		records = append(records, &Record{
			StoreID:    item.StoreID,
			RecordID:   item.RecordID,
			OwnerID:    item.OwnerID,
			GameID:     item.GameID,
			Tags:       item.Tags,
			Properties: item.Properties,
			BlobKeys:   item.BlobKeys,
			CreatedAt:  item.CreatedAt,
			UpdatedAt:  item.UpdatedAt,
		})
	}

	if err := cursor.Err(); err != nil {
		return nil, fmt.Errorf("cursor error: %v", err)
	}

	return records, nil
}

// SetMetadata sets metadata for a key
func (s *DocumentDBStore) SetMetadata(ctx context.Context, metadataType, metadataID string, data map[string]interface{}) error {
	now := time.Now().Unix()

	filter := bson.M{
		"metadata_type": metadataType,
		"metadata_id":   metadataID,
	}

	update := bson.M{
		"$set": bson.M{
			"data":       data,
			"updated_at": now,
		},
		"$setOnInsert": bson.M{
			"metadata_type": metadataType,
			"metadata_id":   metadataID,
			"created_at":    now,
		},
	}

	opts := options.Update().SetUpsert(true)
	_, err := s.metadata.UpdateOne(ctx, filter, update, opts)
	if err != nil {
		return fmt.Errorf("failed to set metadata: %v", err)
	}

	return nil
}

// GetMetadata gets metadata for a key
func (s *DocumentDBStore) GetMetadata(ctx context.Context, metadataType, metadataID string) (map[string]interface{}, error) {
	var item DocumentDBMetadataItem
	err := s.metadata.FindOne(ctx, bson.M{
		"metadata_type": metadataType,
		"metadata_id":   metadataID,
	}).Decode(&item)
	
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("metadata not found: %s/%s", metadataType, metadataID)
		}
		return nil, fmt.Errorf("failed to get metadata: %v", err)
	}

	return item.Data, nil
}

// DeleteMetadata deletes metadata for a key
func (s *DocumentDBStore) DeleteMetadata(ctx context.Context, metadataType, metadataID string) error {
	result, err := s.metadata.DeleteOne(ctx, bson.M{
		"metadata_type": metadataType,
		"metadata_id":   metadataID,
	})
	if err != nil {
		return fmt.Errorf("failed to delete metadata: %v", err)
	}

	if result.DeletedCount == 0 {
		return fmt.Errorf("metadata not found: %s/%s", metadataType, metadataID)
	}

	return nil
}

// QueryMetadata queries metadata with filters
func (s *DocumentDBStore) QueryMetadata(ctx context.Context, metadataType string, limit int32) ([]map[string]interface{}, error) {
	filter := bson.M{"metadata_type": metadataType}

	opts := options.Find()
	if limit > 0 {
		opts.SetLimit(int64(limit))
	}
	opts.SetSort(bson.M{"created_at": -1}) // Sort by creation time, newest first

	cursor, err := s.metadata.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query metadata: %v", err)
	}
	defer cursor.Close(ctx)

	var results []map[string]interface{}
	for cursor.Next(ctx) {
		var item DocumentDBMetadataItem
		if err := cursor.Decode(&item); err != nil {
			return nil, fmt.Errorf("failed to decode metadata: %v", err)
		}

		// Add metadata info to the data
		result := make(map[string]interface{})
		for k, v := range item.Data {
			result[k] = v
		}
		result["metadata_type"] = item.MetadataType
		result["metadata_id"] = item.MetadataID
		result["created_at"] = item.CreatedAt
		result["updated_at"] = item.UpdatedAt

		results = append(results, result)
	}

	if err := cursor.Err(); err != nil {
		return nil, fmt.Errorf("cursor error: %v", err)
	}

	return results, nil
}

// Close closes the DocumentDB connection
func (s *DocumentDBStore) Close(ctx context.Context) error {
	return s.client.Disconnect(ctx)
}
