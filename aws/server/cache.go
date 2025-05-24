package server

import (
	"context"
)

// Cache defines the interface for caching operations
type Cache interface {
	GetStore(ctx context.Context, storeID string) (*StoreInfo, error)
	SetStore(ctx context.Context, store *StoreInfo) error
	DeleteStore(ctx context.Context, storeID string) error
	GetRecord(ctx context.Context, storeID, recordID string) (*Record, error)
	SetRecord(ctx context.Context, record *Record) error
	DeleteRecord(ctx context.Context, storeID, recordID string) error
}

// NoOpCache implements the Cache interface but does nothing
type NoOpCache struct{}

// GetStore returns a not found error
func (c *NoOpCache) GetStore(ctx context.Context, storeID string) (*StoreInfo, error) {
	return nil, ErrNotFound
}

// SetStore does nothing
func (c *NoOpCache) SetStore(ctx context.Context, store *StoreInfo) error {
	return nil
}

// DeleteStore does nothing
func (c *NoOpCache) DeleteStore(ctx context.Context, storeID string) error {
	return nil
}

// GetRecord returns a not found error
func (c *NoOpCache) GetRecord(ctx context.Context, storeID, recordID string) (*Record, error) {
	return nil, ErrNotFound
}

// SetRecord does nothing
func (c *NoOpCache) SetRecord(ctx context.Context, record *Record) error {
	return nil
}

// DeleteRecord does nothing
func (c *NoOpCache) DeleteRecord(ctx context.Context, storeID, recordID string) error {
	return nil
}

// Equal checks if the cache is a NoOpCache
func (c *NoOpCache) Equal(other Cache) bool {
	_, ok := other.(*NoOpCache)
	return ok
}
