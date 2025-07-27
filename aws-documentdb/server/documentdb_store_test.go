package server

import (
	"context"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/integration/mtest"
)

func TestDocumentDBStore_CreateStore(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		// Mock successful count query (store doesn't exist)
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "n", Value: 0}))
		// Mock successful insert
		mt.AddMockResponses(mtest.CreateSuccessResponse())
		// Mock successful metadata insert
		mt.AddMockResponses(mtest.CreateSuccessResponse())

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.Coll,
			records:  mt.DB.Collection("records"),
			metadata: mt.DB.Collection("metadata"),
		}

		err := store.CreateStore(context.Background(), "test-store", "Test Store")
		if err != nil {
			t.Errorf("CreateStore() error = %v", err)
		}
	})

	mt.Run("store already exists", func(mt *mtest.T) {
		// Mock count query returning 1 (store exists)
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "n", Value: 1}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.Coll,
			records:  mt.DB.Collection("records"),
			metadata: mt.DB.Collection("metadata"),
		}

		err := store.CreateStore(context.Background(), "test-store", "Test Store")
		if err == nil {
			t.Error("CreateStore() expected error for existing store")
		}
	})
}

func TestDocumentDBStore_GetStore(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		now := time.Now().Unix()
		// Mock successful find
		mt.AddMockResponses(mtest.CreateCursorResponse(1, "test.stores", mtest.FirstBatch, bson.D{
			{Key: "store_id", Value: "test-store"},
			{Key: "name", Value: "Test Store"},
			{Key: "created_at", Value: now},
			{Key: "updated_at", Value: now},
		}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.Coll,
			records:  mt.DB.Collection("records"),
			metadata: mt.DB.Collection("metadata"),
		}

		result, err := store.GetStore(context.Background(), "test-store")
		if err != nil {
			t.Errorf("GetStore() error = %v", err)
		}

		if result.StoreID != "test-store" {
			t.Errorf("GetStore() StoreID = %v, want %v", result.StoreID, "test-store")
		}
		if result.Name != "Test Store" {
			t.Errorf("GetStore() Name = %v, want %v", result.Name, "Test Store")
		}
	})

	mt.Run("store not found", func(mt *mtest.T) {
		// Mock no documents found
		mt.AddMockResponses(mtest.CreateCursorResponse(0, "test.stores", mtest.FirstBatch))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.Coll,
			records:  mt.DB.Collection("records"),
			metadata: mt.DB.Collection("metadata"),
		}

		_, err := store.GetStore(context.Background(), "nonexistent-store")
		if err == nil {
			t.Error("GetStore() expected error for nonexistent store")
		}
	})
}

func TestDocumentDBStore_CreateRecord(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		// Mock successful count query (record doesn't exist)
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "n", Value: 0}))
		// Mock successful record insert
		mt.AddMockResponses(mtest.CreateSuccessResponse())
		// Mock successful metadata insert
		mt.AddMockResponses(mtest.CreateSuccessResponse())

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.Coll,
			metadata: mt.DB.Collection("metadata"),
		}

		tags := []string{"tag1", "tag2"}
		properties := map[string]interface{}{"key": "value"}
		blobKeys := []string{"blob1", "blob2"}

		err := store.CreateRecord(context.Background(), "test-store", "test-record", "owner1", "game1", tags, properties, blobKeys)
		if err != nil {
			t.Errorf("CreateRecord() error = %v", err)
		}
	})

	mt.Run("record already exists", func(mt *mtest.T) {
		// Mock count query returning 1 (record exists)
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "n", Value: 1}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.Coll,
			metadata: mt.DB.Collection("metadata"),
		}

		err := store.CreateRecord(context.Background(), "test-store", "test-record", "owner1", "game1", nil, nil, nil)
		if err == nil {
			t.Error("CreateRecord() expected error for existing record")
		}
	})
}

func TestDocumentDBStore_GetRecord(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		now := time.Now().Unix()
		// Mock successful find
		mt.AddMockResponses(mtest.CreateCursorResponse(1, "test.records", mtest.FirstBatch, bson.D{
			{Key: "store_id", Value: "test-store"},
			{Key: "record_id", Value: "test-record"},
			{Key: "concat_key", Value: "test-store#test-record"},
			{Key: "owner_id", Value: "owner1"},
			{Key: "game_id", Value: "game1"},
			{Key: "tags", Value: bson.A{"tag1", "tag2"}},
			{Key: "properties", Value: bson.D{{Key: "key", Value: "value"}}},
			{Key: "blob_keys", Value: bson.A{"blob1", "blob2"}},
			{Key: "created_at", Value: now},
			{Key: "updated_at", Value: now},
		}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.Coll,
			metadata: mt.DB.Collection("metadata"),
		}

		result, err := store.GetRecord(context.Background(), "test-store", "test-record")
		if err != nil {
			t.Errorf("GetRecord() error = %v", err)
		}

		if result.StoreID != "test-store" {
			t.Errorf("GetRecord() StoreID = %v, want %v", result.StoreID, "test-store")
		}
		if result.RecordID != "test-record" {
			t.Errorf("GetRecord() RecordID = %v, want %v", result.RecordID, "test-record")
		}
		if result.OwnerID != "owner1" {
			t.Errorf("GetRecord() OwnerID = %v, want %v", result.OwnerID, "owner1")
		}
	})

	mt.Run("record not found", func(mt *mtest.T) {
		// Mock no documents found
		mt.AddMockResponses(mtest.CreateCursorResponse(0, "test.records", mtest.FirstBatch))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.Coll,
			metadata: mt.DB.Collection("metadata"),
		}

		_, err := store.GetRecord(context.Background(), "test-store", "nonexistent-record")
		if err == nil {
			t.Error("GetRecord() expected error for nonexistent record")
		}
	})
}

func TestDocumentDBStore_QueryRecords(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		now := time.Now().Unix()
		// Mock successful find with multiple results
		first := mtest.CreateCursorResponse(1, "test.records", mtest.FirstBatch, bson.D{
			{Key: "store_id", Value: "test-store"},
			{Key: "record_id", Value: "record1"},
			{Key: "concat_key", Value: "test-store#record1"},
			{Key: "owner_id", Value: "owner1"},
			{Key: "game_id", Value: "game1"},
			{Key: "tags", Value: bson.A{"tag1"}},
			{Key: "created_at", Value: now},
			{Key: "updated_at", Value: now},
		})
		second := mtest.CreateCursorResponse(1, "test.records", mtest.NextBatch, bson.D{
			{Key: "store_id", Value: "test-store"},
			{Key: "record_id", Value: "record2"},
			{Key: "concat_key", Value: "test-store#record2"},
			{Key: "owner_id", Value: "owner1"},
			{Key: "game_id", Value: "game1"},
			{Key: "tags", Value: bson.A{"tag2"}},
			{Key: "created_at", Value: now},
			{Key: "updated_at", Value: now},
		})
		killCursors := mtest.CreateCursorResponse(0, "test.records", mtest.NextBatch)
		mt.AddMockResponses(first, second, killCursors)

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.Coll,
			metadata: mt.DB.Collection("metadata"),
		}

		results, err := store.QueryRecords(context.Background(), "test-store", "owner1", "game1", []string{"tag1"}, 10)
		if err != nil {
			t.Errorf("QueryRecords() error = %v", err)
		}

		if len(results) != 2 {
			t.Errorf("QueryRecords() returned %d results, want 2", len(results))
		}
	})
}

func TestDocumentDBStore_SetMetadata(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		// Mock successful upsert
		mt.AddMockResponses(mtest.CreateSuccessResponse(bson.E{Key: "upsertedCount", Value: 1}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.DB.Collection("records"),
			metadata: mt.Coll,
		}

		data := map[string]interface{}{"key": "value"}
		err := store.SetMetadata(context.Background(), "test-type", "test-id", data)
		if err != nil {
			t.Errorf("SetMetadata() error = %v", err)
		}
	})
}

func TestDocumentDBStore_GetMetadata(t *testing.T) {
	mt := mtest.New(t, mtest.NewOptions().ClientType(mtest.Mock))
	defer mt.Close()

	mt.Run("success", func(mt *mtest.T) {
		now := time.Now().Unix()
		// Mock successful find
		mt.AddMockResponses(mtest.CreateCursorResponse(1, "test.metadata", mtest.FirstBatch, bson.D{
			{Key: "metadata_type", Value: "test-type"},
			{Key: "metadata_id", Value: "test-id"},
			{Key: "data", Value: bson.D{{Key: "key", Value: "value"}}},
			{Key: "created_at", Value: now},
			{Key: "updated_at", Value: now},
		}))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.DB.Collection("records"),
			metadata: mt.Coll,
		}

		result, err := store.GetMetadata(context.Background(), "test-type", "test-id")
		if err != nil {
			t.Errorf("GetMetadata() error = %v", err)
		}

		if result["key"] != "value" {
			t.Errorf("GetMetadata() data[key] = %v, want %v", result["key"], "value")
		}
	})

	mt.Run("metadata not found", func(mt *mtest.T) {
		// Mock no documents found
		mt.AddMockResponses(mtest.CreateCursorResponse(0, "test.metadata", mtest.FirstBatch))

		store := &DocumentDBStore{
			client:   mt.Client,
			database: mt.DB,
			stores:   mt.DB.Collection("stores"),
			records:  mt.DB.Collection("records"),
			metadata: mt.Coll,
		}

		_, err := store.GetMetadata(context.Background(), "test-type", "nonexistent-id")
		if err == nil {
			t.Error("GetMetadata() expected error for nonexistent metadata")
		}
	})
}
