package server

import (
	"context"
	"time"
)

// StoreInfo represents a store
type StoreInfo struct {
	StoreID   string    `json:"store_id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Record represents a record in a store
type Record struct {
	StoreID    string                 `json:"store_id"`
	RecordID   string                 `json:"record_id"`
	OwnerID    string                 `json:"owner_id,omitempty"`
	Tags       []string               `json:"tags,omitempty"`
	Properties map[string]interface{} `json:"properties,omitempty"`
	BlobKeys   []string               `json:"blob_keys,omitempty"`
	CreatedAt  time.Time              `json:"created_at"`
	UpdatedAt  time.Time              `json:"updated_at"`
}

// Query represents a query for records
type Query struct {
	Filter string `json:"filter,omitempty"`
	Limit  int    `json:"limit,omitempty"`
}

// Store defines the interface for store operations
type Store interface {
	// Store operations
	CreateStore(ctx context.Context, storeID, name string) error
	GetStore(ctx context.Context, storeID string) (*StoreInfo, error)
	ListStores(ctx context.Context) ([]*StoreInfo, error)
	DeleteStore(ctx context.Context, storeID string) error

	// Record operations
	CreateRecord(ctx context.Context, storeID, recordID string, record *Record) error
	GetRecord(ctx context.Context, storeID, recordID string) (*Record, error)
	QueryRecords(ctx context.Context, storeID string, query *Query) ([]*Record, error)
	UpdateRecord(ctx context.Context, storeID, recordID string, record *Record) error
	DeleteRecord(ctx context.Context, storeID, recordID string) error

	// Metadata operations
	GetMetadata(ctx context.Context, metadataType, metadataID string) (map[string]interface{}, error)
	SetMetadata(ctx context.Context, metadataType, metadataID string, data map[string]interface{}) error
	DeleteMetadata(ctx context.Context, metadataType, metadataID string) error
	QueryMetadata(ctx context.Context, metadataType string) ([]map[string]interface{}, error)
}
