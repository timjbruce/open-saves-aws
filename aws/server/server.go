package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

// Server represents the Open Saves server
type Server struct {
	config    *Config
	store     Store
	blobStore BlobStore
	cache     Cache
	grpcSrv   *grpc.Server
}

// NewServer creates a new Open Saves server
func NewServer(config *Config) (*Server, error) {
	// Create DynamoDB store with separate tables for stores, records, and metadata
	store, err := NewDynamoDBStore(
		config.AWS.Region,
		config.AWS.DynamoDB.StoresTable,
		config.AWS.DynamoDB.RecordsTable,
		config.AWS.DynamoDB.MetadataTable,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create DynamoDB store: %v", err)
	}

	// Create S3 blob store
	blobStore, err := NewS3BlobStore(config.AWS.Region, config.AWS.S3.BucketName)
	if err != nil {
		return nil, fmt.Errorf("failed to create S3 blob store: %v", err)
	}

	// Create Redis cache or use NoOpCache if Redis is not available
	var cache Cache = &NoOpCache{}
	if config.AWS.ElastiCache.Address != "" {
		// Use a shorter timeout for Redis connection
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		
		redisCache, err := NewRedisCache(ctx, config.AWS.ElastiCache.Address, config.AWS.ElastiCache.TTL)
		if err != nil {
			log.Printf("Warning: Failed to create Redis cache: %v. Continuing with NoOpCache.", err)
			// Ensure we're using NoOpCache (already set above)
		} else {
			cache = redisCache
			log.Printf("Successfully connected to Redis cache at %s", config.AWS.ElastiCache.Address)
		}
	} else {
		log.Printf("No Redis address configured. Using NoOpCache.")
	}

	// Create gRPC server
	grpcSrv := grpc.NewServer()
	reflection.Register(grpcSrv)

	return &Server{
		config:    config,
		store:     store,
		blobStore: blobStore,
		cache:     cache,
		grpcSrv:   grpcSrv,
	}, nil
}

// Start starts the server
func (s *Server) Start() error {
	// Start gRPC server
	go func() {
		addr := fmt.Sprintf(":%d", s.config.Server.GRPCPort)
		lis, err := net.Listen("tcp", addr)
		if err != nil {
			log.Fatalf("Failed to listen on %s: %v", addr, err)
		}
		log.Printf("gRPC server listening on %s", addr)
		if err := s.grpcSrv.Serve(lis); err != nil {
			log.Fatalf("Failed to serve gRPC: %v", err)
		}
	}()

	// Start HTTP server
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	mux := http.NewServeMux()

	// Add HTTP handlers
	mux.HandleFunc("/", s.handleRoot)
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/api/stores", s.handleStores)
	mux.HandleFunc("/api/stores/", s.handleStoreOrRecord)
	mux.HandleFunc("/api/metadata/", s.handleMetadata)

	addr := fmt.Sprintf(":%d", s.config.Server.HTTPPort)
	log.Printf("HTTP server listening on %s", addr)
	return http.ListenAndServe(addr, mux)
}

// Stop stops the server
func (s *Server) Stop() {
	s.grpcSrv.GracefulStop()
	if s.cache != nil {
		if closer, ok := s.cache.(io.Closer); ok {
			closer.Close()
		}
	}
}

// handleRoot handles the root endpoint
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	fmt.Fprintf(w, "Open Saves AWS Adapter is running!")
}

// handleHealth handles the health endpoint
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "OK")
}

// handleStores handles the /api/stores endpoint
func (s *Server) handleStores(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	switch r.Method {
	case http.MethodGet:
		// List stores
		stores, err := s.store.ListStores(ctx)
		if err != nil {
			log.Printf("Failed to list stores: %v", err)
			http.Error(w, "Failed to list stores", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"stores": stores,
		})

	case http.MethodPost:
		// Create store
		var storeData struct {
			StoreID string `json:"store_id"`
			Name    string `json:"name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&storeData); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if storeData.StoreID == "" {
			http.Error(w, "store_id is required", http.StatusBadRequest)
			return
		}

		// Check if store already exists
		_, err := s.store.GetStore(ctx, storeData.StoreID)
		if err == nil {
			http.Error(w, "store already exists", http.StatusConflict)
			return
		}

		// Create the store
		if err := s.store.CreateStore(ctx, storeData.StoreID, storeData.Name); err != nil {
			log.Printf("Failed to create store: %v", err)
			http.Error(w, "Failed to create store", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleStoreOrRecord handles the /api/stores/{storeID} and /api/stores/{storeID}/records endpoints
func (s *Server) handleStoreOrRecord(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/stores/")
	parts := strings.Split(path, "/")

	if len(parts) == 1 {
		// Handle store operations
		s.handleStore(w, r, parts[0])
	} else if len(parts) >= 2 && parts[1] == "records" {
		// Handle record operations
		if len(parts) == 2 {
			s.handleRecords(w, r, parts[0])
		} else if len(parts) == 3 {
			s.handleRecord(w, r, parts[0], parts[2])
		} else if len(parts) >= 4 && parts[3] == "blobs" {
			if len(parts) == 4 {
				s.handleBlobs(w, r, parts[0], parts[2])
			} else if len(parts) == 5 {
				s.handleBlob(w, r, parts[0], parts[2], parts[4])
			} else {
				http.NotFound(w, r)
			}
		} else {
			http.NotFound(w, r)
		}
	} else {
		http.NotFound(w, r)
	}
}

// handleStore handles operations on a specific store
func (s *Server) handleStore(w http.ResponseWriter, r *http.Request, storeID string) {
	ctx := r.Context()

	switch r.Method {
	case http.MethodGet:
		// Get store directly from DynamoDB without trying to use cache first
		// This avoids nil pointer dereferences if the cache is not properly initialized
		store, err := s.store.GetStore(ctx, storeID)
		if err != nil {
			log.Printf("Failed to get store: %v", err)
			http.Error(w, "store not found", http.StatusNotFound)
			return
		}

		// Only try to cache the store if we have a valid cache implementation
		if s.cache != nil {
			// Check if it's not a NoOpCache before trying to use it
			if noopCache, ok := s.cache.(*NoOpCache); !ok || noopCache == nil {
				// Ignore cache errors - just log them
				if err := s.cache.SetStore(ctx, store); err != nil {
					log.Printf("Failed to cache store: %v", err)
				}
			}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(store)

	case http.MethodDelete:
		// Delete store
		if err := s.store.DeleteStore(ctx, storeID); err != nil {
			log.Printf("Failed to delete store: %v", err)
			http.Error(w, "Failed to delete store", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusNoContent)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleRecords handles operations on records in a store
func (s *Server) handleRecords(w http.ResponseWriter, r *http.Request, storeID string) {
	ctx := r.Context()

	// Check if store exists
	_, err := s.store.GetStore(ctx, storeID)
	if err != nil {
		http.Error(w, "store not found", http.StatusNotFound)
		return
	}

	switch r.Method {
	case http.MethodGet:
		// Query records
		ownerID := r.URL.Query().Get("owner_id")
		gameID := r.URL.Query().Get("game_id")
		limitStr := r.URL.Query().Get("limit")
		
		var limit int
		if limitStr != "" {
			limit, err = strconv.Atoi(limitStr)
			if err != nil || limit < 0 {
				limit = 0
			}
		}
		
		query := &Query{
			OwnerID: ownerID,
			GameID:  gameID,
			Limit:   limit,
		}
		
		records, err := s.store.QueryRecords(ctx, storeID, query)
		if err != nil {
			log.Printf("Failed to query records: %v", err)
			http.Error(w, "Failed to query records", http.StatusInternalServerError)
			return
		}
		
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"records": records,
		})

	case http.MethodPost:
		// Create record
		var recordData map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&recordData); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		recordID, ok := recordData["record_id"].(string)
		if !ok || recordID == "" {
			http.Error(w, "record_id is required", http.StatusBadRequest)
			return
		}

		now := time.Now()
		record := &Record{
			StoreID:    storeID,
			RecordID:   recordID,
			CreatedAt:  now,
			UpdatedAt:  now,
			Properties: make(map[string]interface{}),
		}

		if ownerID, ok := recordData["owner_id"].(string); ok {
			record.OwnerID = ownerID
		}

		if tags, ok := recordData["tags"].([]interface{}); ok {
			record.Tags = make([]string, len(tags))
			for i, tag := range tags {
				if tagStr, ok := tag.(string); ok {
					record.Tags[i] = tagStr
				}
			}
		}

		if props, ok := recordData["properties"].(map[string]interface{}); ok {
			record.Properties = props
		}

		if err := s.store.CreateRecord(ctx, storeID, recordID, record); err != nil {
			log.Printf("Failed to create record: %v", err)
			http.Error(w, "Failed to create record", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleRecord handles operations on a specific record
func (s *Server) handleRecord(w http.ResponseWriter, r *http.Request, storeID, recordID string) {
	ctx := r.Context()

	switch r.Method {
	case http.MethodGet:
		// Get record directly from DynamoDB without trying to use cache first
		// This avoids nil pointer dereferences if the cache is not properly initialized
		record, err := s.store.GetRecord(ctx, storeID, recordID)
		if err != nil {
			log.Printf("Failed to get record: %v", err)
			http.Error(w, "record not found", http.StatusNotFound)
			return
		}

		// Only try to cache the record if we have a valid cache implementation
		if s.cache != nil {
			// Check if it's not a NoOpCache before trying to use it
			if noopCache, ok := s.cache.(*NoOpCache); !ok || noopCache == nil {
				// Ignore cache errors - just log them
				if err := s.cache.SetRecord(ctx, record); err != nil {
					log.Printf("Failed to cache record: %v", err)
				}
			}
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(record)

	case http.MethodPut:
		// Update record
		var recordData map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&recordData); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		// Get existing record
		record, err := s.store.GetRecord(ctx, storeID, recordID)
		if err != nil {
			log.Printf("Failed to get record for update: %v", err)
			http.Error(w, "record not found", http.StatusNotFound)
			return
		}

		// Update fields
		if ownerID, ok := recordData["owner_id"].(string); ok {
			record.OwnerID = ownerID
		}

		if tags, ok := recordData["tags"].([]interface{}); ok {
			record.Tags = make([]string, len(tags))
			for i, tag := range tags {
				if tagStr, ok := tag.(string); ok {
					record.Tags[i] = tagStr
				}
			}
		}

		if props, ok := recordData["properties"].(map[string]interface{}); ok {
			record.Properties = props
		}

		record.UpdatedAt = time.Now()

		// Update the record
		if err := s.store.UpdateRecord(ctx, storeID, recordID, record); err != nil {
			log.Printf("Failed to update record: %v", err)
			http.Error(w, "Failed to update record", http.StatusInternalServerError)
			return
		}

		// Invalidate cache entry if it exists
		if s.cache != nil {
			if noopCache, ok := s.cache.(*NoOpCache); !ok || noopCache == nil {
				if err := s.cache.DeleteRecord(ctx, storeID, recordID); err != nil {
					log.Printf("Failed to invalidate cache for updated record: %v", err)
					// Continue anyway, the record was updated successfully
				}
			}
		}

		w.WriteHeader(http.StatusOK)

	case http.MethodDelete:
		// Delete record
		if err := s.store.DeleteRecord(ctx, storeID, recordID); err != nil {
			log.Printf("Failed to delete record: %v", err)
			http.Error(w, "Failed to delete record", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusNoContent)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleBlobs handles operations on blobs in a record
func (s *Server) handleBlobs(w http.ResponseWriter, r *http.Request, storeID, recordID string) {
	ctx := r.Context()

	// Check if record exists - get directly from DynamoDB to avoid cache issues
	record, err := s.store.GetRecord(ctx, storeID, recordID)
	if err != nil {
		log.Printf("Failed to get record for blobs operation: %v", err)
		http.Error(w, "record not found", http.StatusNotFound)
		return
	}

	switch r.Method {
	case http.MethodGet:
		// List blobs
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(record.BlobKeys)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleBlob handles operations on a specific blob
func (s *Server) handleBlob(w http.ResponseWriter, r *http.Request, storeID, recordID, blobKey string) {
	ctx := r.Context()

	// Check if record exists - get directly from DynamoDB to avoid cache issues
	record, err := s.store.GetRecord(ctx, storeID, recordID)
	if err != nil {
		log.Printf("Failed to get record for blob operation: %v", err)
		http.Error(w, "record not found", http.StatusNotFound)
		return
	}

	switch r.Method {
	case http.MethodGet:
		// Get blob from S3
		reader, size, err := s.blobStore.Get(ctx, storeID, recordID, blobKey)
		if err != nil {
			log.Printf("Failed to get blob: %v", err)
			http.Error(w, "blob not found", http.StatusNotFound)
			return
		}
		defer reader.Close()

		// Set content length header
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", fmt.Sprintf("%d", size))

		// Copy the blob data to the response
		if _, err := io.Copy(w, reader); err != nil {
			log.Printf("Failed to write blob data: %v", err)
			http.Error(w, "Failed to write blob data", http.StatusInternalServerError)
			return
		}

	case http.MethodPut:
		// Upload blob to S3
		data, err := ioutil.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		// Upload to S3
		err = s.blobStore.Put(ctx, storeID, recordID, blobKey, strings.NewReader(string(data)), int64(len(data)))
		if err != nil {
			log.Printf("Failed to upload blob: %v", err)
			http.Error(w, "Failed to upload blob", http.StatusInternalServerError)
			return
		}

		// Update record with blob key if not already present
		blobKeyExists := false
		for _, key := range record.BlobKeys {
			if key == blobKey {
				blobKeyExists = true
				break
			}
		}

		if !blobKeyExists {
			record.BlobKeys = append(record.BlobKeys, blobKey)
			record.UpdatedAt = time.Now()
			if err := s.store.UpdateRecord(ctx, storeID, recordID, record); err != nil {
				log.Printf("Failed to update record with blob key: %v", err)
				// Continue anyway, the blob was uploaded successfully
			}
		}

		w.WriteHeader(http.StatusOK)

	case http.MethodDelete:
		// Delete blob from S3
		err := s.blobStore.Delete(ctx, storeID, recordID, blobKey)
		if err != nil {
			log.Printf("Failed to delete blob: %v", err)
			http.Error(w, "Failed to delete blob", http.StatusInternalServerError)
			return
		}

		// Update record to remove blob key
		newBlobKeys := make([]string, 0, len(record.BlobKeys))
		for _, key := range record.BlobKeys {
			if key != blobKey {
				newBlobKeys = append(newBlobKeys, key)
			}
		}

		record.BlobKeys = newBlobKeys
		record.UpdatedAt = time.Now()
		if err := s.store.UpdateRecord(ctx, storeID, recordID, record); err != nil {
			log.Printf("Failed to update record after blob deletion: %v", err)
			// Continue anyway, the blob was deleted successfully
		}

		w.WriteHeader(http.StatusNoContent)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}

// handleMetadata handles operations on metadata
func (s *Server) handleMetadata(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	path := strings.TrimPrefix(r.URL.Path, "/api/metadata/")
	parts := strings.Split(path, "/")

	if len(parts) != 2 {
		http.Error(w, "Invalid metadata path", http.StatusBadRequest)
		return
	}

	metadataType := parts[0]
	metadataID := parts[1]

	switch r.Method {
	case http.MethodGet:
		// Get metadata
		data, err := s.store.GetMetadata(ctx, metadataType, metadataID)
		if err != nil {
			log.Printf("Failed to get metadata: %v", err)
			http.Error(w, "metadata not found", http.StatusNotFound)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(data)

	case http.MethodPost:
		// Create or update metadata
		var data map[string]interface{}
		if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		if err := s.store.SetMetadata(ctx, metadataType, metadataID, data); err != nil {
			log.Printf("Failed to set metadata: %v", err)
			http.Error(w, "Failed to set metadata", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)

	case http.MethodDelete:
		// Delete metadata
		if err := s.store.DeleteMetadata(ctx, metadataType, metadataID); err != nil {
			log.Printf("Failed to delete metadata: %v", err)
			http.Error(w, "Failed to delete metadata", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusNoContent)

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}
