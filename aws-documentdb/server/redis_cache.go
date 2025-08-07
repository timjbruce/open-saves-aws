package server

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/go-redis/redis/v8"
)

// RedisCache implements the Cache interface using Redis
type RedisCache struct {
	client *redis.Client
	ttl    time.Duration
}

// NewRedisCache creates a new Redis cache
func NewRedisCache(ctx context.Context, address string, ttlSeconds int) (*RedisCache, error) {
	client := redis.NewClient(&redis.Options{
		Addr:        address,
		Password:    "", // no password
		DB:          0,  // use default DB
		DialTimeout: 2 * time.Second,
		ReadTimeout: 2 * time.Second,
	})

	// Test connection with the provided context
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %v", err)
	}

	return &RedisCache{
		client: client,
		ttl:    time.Duration(ttlSeconds) * time.Second,
	}, nil
}

// Close closes the Redis client
func (c *RedisCache) Close() error {
	return c.client.Close()
}

// GetStore gets a store from the cache
func (c *RedisCache) GetStore(ctx context.Context, storeID string) (*StoreInfo, error) {
	key := fmt.Sprintf("store:%s", storeID)
	data, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		if err == redis.Nil {
			return nil, fmt.Errorf("store not found in cache")
		}
		return nil, err
	}

	var store StoreInfo
	if err := json.Unmarshal(data, &store); err != nil {
		return nil, err
	}

	return &store, nil
}

// SetStore sets a store in the cache
func (c *RedisCache) SetStore(ctx context.Context, store *StoreInfo) error {
	key := fmt.Sprintf("store:%s", store.StoreID)
	data, err := json.Marshal(store)
	if err != nil {
		return err
	}

	return c.client.Set(ctx, key, data, c.ttl).Err()
}

// DeleteStore deletes a store from the cache
func (c *RedisCache) DeleteStore(ctx context.Context, storeID string) error {
	key := fmt.Sprintf("store:%s", storeID)
	return c.client.Del(ctx, key).Err()
}

// GetRecord gets a record from the cache
func (c *RedisCache) GetRecord(ctx context.Context, storeID, recordID string) (*Record, error) {
	if c == nil || c.client == nil {
		return nil, fmt.Errorf("cache not initialized")
	}
	
	key := fmt.Sprintf("record:%s:%s", storeID, recordID)
	data, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		if err == redis.Nil {
			return nil, fmt.Errorf("record not found in cache")
		}
		return nil, err
	}

	var record Record
	if err := json.Unmarshal(data, &record); err != nil {
		return nil, err
	}

	return &record, nil
}

// SetRecord sets a record in the cache
func (c *RedisCache) SetRecord(ctx context.Context, record *Record) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache not initialized")
	}
	
	key := fmt.Sprintf("record:%s:%s", record.StoreID, record.RecordID)
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}

	return c.client.Set(ctx, key, data, c.ttl).Err()
}

// DeleteRecord deletes a record from the cache
func (c *RedisCache) DeleteRecord(ctx context.Context, storeID, recordID string) error {
	if c == nil || c.client == nil {
		return fmt.Errorf("cache not initialized")
	}
	
	key := fmt.Sprintf("record:%s:%s", storeID, recordID)
	return c.client.Del(ctx, key).Err()
}
