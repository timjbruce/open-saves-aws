package server

import (
	"context"
	"io"
)

// BlobStore defines the interface for blob storage operations
type BlobStore interface {
	// Get retrieves a blob
	Get(ctx context.Context, storeID, recordID, blobKey string) (io.ReadCloser, int64, error)
	
	// Put uploads a blob
	Put(ctx context.Context, storeID, recordID, blobKey string, data io.Reader, size int64) error
	
	// Delete removes a blob
	Delete(ctx context.Context, storeID, recordID, blobKey string) error
	
	// List returns all blob keys for a record
	List(ctx context.Context, storeID, recordID string) ([]string, error)
}
