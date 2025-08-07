package server

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// getPasswordFromSecretsManager retrieves the password from AWS Secrets Manager
func getPasswordFromSecretsManager(secretArn string) (string, error) {
	// Get AWS region from environment variable or use default
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1" // Default region
	}

	// Create AWS session with region
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		return "", fmt.Errorf("failed to create AWS session: %v", err)
	}

	// Create Secrets Manager client
	svc := secretsmanager.New(sess)

	// Get secret value
	result, err := svc.GetSecretValue(&secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretArn),
	})
	if err != nil {
		return "", fmt.Errorf("failed to get secret value: %v", err)
	}

	if result.SecretString == nil {
		return "", fmt.Errorf("secret value is nil")
	}

	return *result.SecretString, nil
}

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

// createTLSConfig creates a proper TLS configuration for DocumentDB
func createTLSConfig() (*tls.Config, error) {
	// Check if we should skip certificate verification (for testing only)
	if skipVerify := os.Getenv("SKIP_TLS_VERIFY"); skipVerify == "true" {
		log.Println("WARNING: Skipping TLS certificate verification - NOT for production use!")
		return &tls.Config{
			InsecureSkipVerify: true,
		}, nil
	}

	// Path to the global bundle certificate (downloaded in Dockerfile)
	certPath := "/etc/ssl/certs/global-bundle.pem"
	log.Printf("DEBUG: Attempting to read certificate from: %s", certPath)
	
	// Check if file exists
	if _, err := os.Stat(certPath); os.IsNotExist(err) {
		log.Printf("ERROR: Certificate file does not exist: %s", certPath)
		return nil, fmt.Errorf("certificate file does not exist: %s", certPath)
	}
	log.Printf("DEBUG: Certificate file exists")
	
	// Load the DocumentDB CA certificate
	caCert, err := ioutil.ReadFile(certPath)
	if err != nil {
		log.Printf("ERROR: Failed to read certificate file: %v", err)
		return nil, fmt.Errorf("failed to read CA certificate from %s: %v", certPath, err)
	}
	log.Printf("DEBUG: Successfully read certificate file (%d bytes)", len(caCert))

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCert) {
		log.Printf("ERROR: Failed to parse certificate PEM data")
		return nil, fmt.Errorf("failed to parse CA certificate")
	}
	log.Printf("DEBUG: Successfully parsed certificate and added to CA pool")

	tlsConfig := &tls.Config{
		RootCAs: caCertPool,
	}
	log.Printf("DEBUG: TLS config created successfully")

	return tlsConfig, nil
}

// NewDocumentDBStore creates a new DocumentDB store
func NewDocumentDBStore(connectionString, passwordSecretArn, databaseName string) (*DocumentDBStore, error) {
	log.Printf("🚀 NEW CODE: NewDocumentDBStore called with FIXED authentication approach!")
	log.Printf("DEBUG: NewDocumentDBStore called")
	log.Printf("DEBUG: connectionString: %s", connectionString)
	log.Printf("DEBUG: passwordSecretArn: %s", passwordSecretArn)
	log.Printf("DEBUG: databaseName: %s", databaseName)
	
	log.Printf("Connecting to DocumentDB...")
	log.Printf("Database: %s", databaseName)
	
	// Get password from Secrets Manager
	log.Printf("Retrieving password from Secrets Manager...")
	password, err := getPasswordFromSecretsManager(passwordSecretArn)
	if err != nil {
		log.Printf("ERROR: Failed to get password from Secrets Manager: %v", err)
		return nil, fmt.Errorf("failed to get password from Secrets Manager: %v", err)
	}
	log.Printf("Successfully retrieved password from Secrets Manager (length: %d)", len(password))

	// Use the original connection string without any password modification
	// The connection string should be: mongodb://username@host:port/?options
	log.Printf("DEBUG: Using original connection string (no password): %s", connectionString)

	// Set client options with the clean connection string (no password)
	clientOptions := options.Client().ApplyURI(connectionString)
	log.Printf("DEBUG: Connection string applied to client options")

	// Extract username from connection string
	username := "opensaves" // Default username
	if strings.Contains(connectionString, "://") && strings.Contains(connectionString, "@") {
		parts := strings.Split(connectionString, "://")
		if len(parts) > 1 {
			userPart := strings.Split(parts[1], "@")[0]
			if userPart != "" {
				username = userPart
			}
		}
	}
	log.Printf("DEBUG: Extracted username: %s", username)

	// Set authentication credentials separately (no URL encoding needed for SetAuth)
	log.Printf("DEBUG: Setting authentication credentials")
	credential := options.Credential{
		AuthMechanism: "SCRAM-SHA-1",
		AuthSource:    "admin",
		Username:      username,
		Password:      password, // Use raw password, not URL encoded
	}
	clientOptions.SetAuth(credential)
	log.Printf("DEBUG: Authentication credentials set successfully")
	
	log.Printf("DEBUG: About to create TLS config")
	// Configure TLS to use DocumentDB CA certificate
	tlsConfig, err := createTLSConfig()
	if err != nil {
		log.Printf("ERROR: Failed to create TLS config: %v", err)
		return nil, fmt.Errorf("failed to create TLS config: %v", err)
	}
	log.Printf("DEBUG: TLS config created successfully")
	clientOptions.SetTLSConfig(tlsConfig)
	log.Printf("DEBUG: TLS config set on client options")

	// Create a new client and connect to the server
	log.Printf("DEBUG: About to connect to MongoDB")
	client, err := mongo.Connect(context.TODO(), clientOptions)
	if err != nil {
		log.Printf("ERROR: Failed to connect to DocumentDB: %v", err)
		return nil, fmt.Errorf("failed to connect to DocumentDB: %v", err)
	}
	log.Printf("DEBUG: MongoDB connection established")

	// Test the connection with a timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	err = client.Ping(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to ping DocumentDB: %v", err)
	}

	log.Println("Successfully connected to DocumentDB!")

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
func (s *DocumentDBStore) GetStore(ctx context.Context, storeID string) (*StoreInfo, error) {
	var item DocumentDBStoreItem
	err := s.stores.FindOne(ctx, bson.M{"store_id": storeID}).Decode(&item)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, fmt.Errorf("store not found: %s", storeID)
		}
		return nil, fmt.Errorf("failed to get store: %v", err)
	}

	return &StoreInfo{
		StoreID:   item.StoreID,
		Name:      item.Name,
		CreatedAt: time.Unix(item.CreatedAt, 0),
		UpdatedAt: time.Unix(item.UpdatedAt, 0),
	}, nil
}

// ListStores lists all stores
func (s *DocumentDBStore) ListStores(ctx context.Context) ([]*StoreInfo, error) {
	cursor, err := s.stores.Find(ctx, bson.M{})
	if err != nil {
		return nil, fmt.Errorf("failed to list stores: %v", err)
	}
	defer cursor.Close(ctx)

	var stores []*StoreInfo
	for cursor.Next(ctx) {
		var item DocumentDBStoreItem
		if err := cursor.Decode(&item); err != nil {
			return nil, fmt.Errorf("failed to decode store: %v", err)
		}

		stores = append(stores, &StoreInfo{
			StoreID:   item.StoreID,
			Name:      item.Name,
			CreatedAt: time.Unix(item.CreatedAt, 0),
			UpdatedAt: time.Unix(item.UpdatedAt, 0),
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
func (s *DocumentDBStore) CreateRecord(ctx context.Context, storeID, recordID string, record *Record) error {
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
		OwnerID:    record.OwnerID,
		GameID:     record.GameID,
		Tags:       record.Tags,
		Properties: record.Properties,
		BlobKeys:   record.BlobKeys,
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
			"owner_id":   record.OwnerID,
			"game_id":    record.GameID,
			"tags":       record.Tags,
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
		CreatedAt:  time.Unix(item.CreatedAt, 0),
		UpdatedAt:  time.Unix(item.UpdatedAt, 0),
	}, nil
}

// UpdateRecord updates an existing record
func (s *DocumentDBStore) UpdateRecord(ctx context.Context, storeID, recordID string, record *Record) error {
	now := time.Now().Unix()
	concatKey := fmt.Sprintf("%s#%s", storeID, recordID)

	update := bson.M{
		"$set": bson.M{
			"owner_id":   record.OwnerID,
			"game_id":    record.GameID,
			"tags":       record.Tags,
			"properties": record.Properties,
			"blob_keys":  record.BlobKeys,
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
func (s *DocumentDBStore) QueryRecords(ctx context.Context, storeID string, query *Query) ([]*Record, error) {
	filter := bson.M{"store_id": storeID}

	if query.OwnerID != "" {
		filter["owner_id"] = query.OwnerID
	}

	if query.GameID != "" {
		filter["game_id"] = query.GameID
	}

	opts := options.Find()
	if query.Limit > 0 {
		opts.SetLimit(int64(query.Limit))
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
			CreatedAt:  time.Unix(item.CreatedAt, 0),
			UpdatedAt:  time.Unix(item.UpdatedAt, 0),
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
func (s *DocumentDBStore) QueryMetadata(ctx context.Context, metadataType string) ([]map[string]interface{}, error) {
	filter := bson.M{"metadata_type": metadataType}

	opts := options.Find()
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
