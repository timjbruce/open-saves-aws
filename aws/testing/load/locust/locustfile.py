"""
Open Saves AWS Load Testing with Locust
"""

import json
import os
import random
import string
import time
import uuid
from typing import Dict, List, Optional

from locust import HttpUser, TaskSet, between, task


def generate_random_id(prefix: str = "", length: int = 8) -> str:
    """Generate a random ID with an optional prefix."""
    random_part = ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))
    return f"{prefix}{random_part}"


def load_json_data(file_path: str) -> Dict:
    """Load JSON data from a file."""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


class StoreOperations(TaskSet):
    """Tasks for store operations."""
    
    def on_start(self):
        """Initialize store operations."""
        self.store_id = generate_random_id("store-")
        self.create_store()
    
    def on_stop(self):
        """Clean up after store operations."""
        self.delete_store()
    
    def create_store(self):
        """Create a new store."""
        store_data = {
            "store_id": self.store_id,
            "name": f"Test Store {self.store_id}"
        }
        
        with self.client.post(
            f"/api/stores",
            json=store_data,
            catch_response=True,
            name="Create Store"
        ) as response:
            if response.status_code == 200:
                self.store_created = True
            else:
                self.store_created = False
                response.failure(f"Failed to create store: {response.status_code}")
    
    def delete_store(self):
        """Delete the store."""
        if not hasattr(self, 'store_created') or not self.store_created:
            return
            
        with self.client.delete(
            f"/api/stores/{self.store_id}",
            catch_response=True,
            name="Delete Store"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete store: {response.status_code}")
    
    @task(3)
    def get_store(self):
        """Get store details."""
        if not hasattr(self, 'store_created') or not self.store_created:
            return
            
        with self.client.get(
            f"/api/stores/{self.store_id}",
            catch_response=True,
            name="Get Store"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to get store: {response.status_code}")
    
    @task(1)
    def list_stores(self):
        """List all stores."""
        with self.client.get(
            "/api/stores",
            catch_response=True,
            name="List Stores"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to list stores: {response.status_code}")


class RecordOperations(TaskSet):
    """Tasks for record operations."""
    
    def on_start(self):
        """Initialize record operations."""
        self.store_id = generate_random_id("store-")
        self.record_id = generate_random_id("record-")
        self.create_store()
        if self.store_created:
            self.create_record()
    
    def on_stop(self):
        """Clean up after record operations."""
        if hasattr(self, 'record_created') and self.record_created:
            self.delete_record()
        if hasattr(self, 'store_created') and self.store_created:
            self.delete_store()
    
    def create_store(self):
        """Create a new store for records."""
        store_data = {
            "store_id": self.store_id,
            "name": f"Record Test Store {self.store_id}"
        }
        
        with self.client.post(
            f"/api/stores",
            json=store_data,
            catch_response=True,
            name="Create Store for Records"
        ) as response:
            if response.status_code == 200:
                self.store_created = True
            else:
                self.store_created = False
                response.failure(f"Failed to create store for records: {response.status_code}")
    
    def create_record(self):
        """Create a new record."""
        record_data = {
            "record_id": self.record_id,
            "owner_id": f"owner-{uuid.uuid4()}",
            "tags": ["test", "locust", random.choice(["game", "save", "profile"])],
            "properties": {
                "score": random.randint(0, 1000),
                "level": random.randint(1, 100),
                "timestamp": int(time.time())
            }
        }
        
        with self.client.post(
            f"/api/stores/{self.store_id}/records",
            json=record_data,
            catch_response=True,
            name="Create Record"
        ) as response:
            if response.status_code == 200:
                self.record_created = True
            else:
                self.record_created = False
                response.failure(f"Failed to create record: {response.status_code}")
    
    def delete_record(self):
        """Delete the record."""
        with self.client.delete(
            f"/api/stores/{self.store_id}/records/{self.record_id}",
            catch_response=True,
            name="Delete Record"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete record: {response.status_code}")
    
    def delete_store(self):
        """Delete the store."""
        with self.client.delete(
            f"/api/stores/{self.store_id}",
            catch_response=True,
            name="Delete Store after Records"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete store after records: {response.status_code}")
    
    @task(5)
    def get_record(self):
        """Get record details."""
        if not hasattr(self, 'record_created') or not self.record_created:
            return
            
        with self.client.get(
            f"/api/stores/{self.store_id}/records/{self.record_id}",
            catch_response=True,
            name="Get Record"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to get record: {response.status_code}")
    
    @task(2)
    def update_record(self):
        """Update record properties."""
        if not hasattr(self, 'record_created') or not self.record_created:
            return
            
        update_data = {
            "properties": {
                "score": random.randint(0, 1000),
                "level": random.randint(1, 100),
                "timestamp": int(time.time())
            }
        }
        
        with self.client.patch(
            f"/api/stores/{self.store_id}/records/{self.record_id}",
            json=update_data,
            catch_response=True,
            name="Update Record"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to update record: {response.status_code}")
    
    @task(1)
    def query_records(self):
        """Query records by owner."""
        if not hasattr(self, 'record_created') or not self.record_created:
            return
            
        with self.client.get(
            f"/api/stores/{self.store_id}/records?owner_id=owner-{uuid.uuid4()}",
            catch_response=True,
            name="Query Records"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to query records: {response.status_code}")


class BlobOperations(TaskSet):
    """Tasks for blob operations."""
    
    def on_start(self):
        """Initialize blob operations."""
        self.store_id = generate_random_id("store-")
        self.record_id = generate_random_id("record-")
        self.blob_id = generate_random_id("blob-")
        self.blob_content = f"Test blob content {uuid.uuid4()}"
        
        self.create_store()
        if self.store_created:
            self.create_record()
    
    def on_stop(self):
        """Clean up after blob operations."""
        if hasattr(self, 'blob_created') and self.blob_created:
            self.delete_blob()
        if hasattr(self, 'record_created') and self.record_created:
            self.delete_record()
        if hasattr(self, 'store_created') and self.store_created:
            self.delete_store()
    
    def create_store(self):
        """Create a new store for blobs."""
        store_data = {
            "store_id": self.store_id,
            "name": f"Blob Test Store {self.store_id}"
        }
        
        with self.client.post(
            f"/api/stores",
            json=store_data,
            catch_response=True,
            name="Create Store for Blobs"
        ) as response:
            if response.status_code == 200:
                self.store_created = True
            else:
                self.store_created = False
                response.failure(f"Failed to create store for blobs: {response.status_code}")
    
    def create_record(self):
        """Create a new record for blobs."""
        record_data = {
            "record_id": self.record_id,
            "owner_id": f"owner-{uuid.uuid4()}",
            "tags": ["blob", "test"],
            "properties": {
                "blob_count": 0
            }
        }
        
        with self.client.post(
            f"/api/stores/{self.store_id}/records",
            json=record_data,
            catch_response=True,
            name="Create Record for Blobs"
        ) as response:
            if response.status_code == 200:
                self.record_created = True
            else:
                self.record_created = False
                response.failure(f"Failed to create record for blobs: {response.status_code}")
    
    @task(2)
    def upload_blob(self):
        """Upload a blob."""
        if not hasattr(self, 'record_created') or not self.record_created:
            return
            
        blob_id = generate_random_id("blob-")
        blob_content = f"Test blob content {uuid.uuid4()}"
        
        with self.client.put(
            f"/api/stores/{self.store_id}/records/{self.record_id}/blobs/{blob_id}",
            data=blob_content,
            headers={"Content-Type": "application/octet-stream"},
            catch_response=True,
            name="Upload Blob"
        ) as response:
            if response.status_code == 200:
                self.blob_created = True
                self.blob_id = blob_id
            else:
                response.failure(f"Failed to upload blob: {response.status_code}")
    
    @task(4)
    def get_blob(self):
        """Get a blob."""
        if not hasattr(self, 'blob_created') or not self.blob_created:
            return
            
        with self.client.get(
            f"/api/stores/{self.store_id}/records/{self.record_id}/blobs/{self.blob_id}",
            catch_response=True,
            name="Get Blob"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to get blob: {response.status_code}")
    
    @task(1)
    def list_blobs(self):
        """List blobs for a record."""
        if not hasattr(self, 'record_created') or not self.record_created:
            return
            
        with self.client.get(
            f"/api/stores/{self.store_id}/records/{self.record_id}/blobs",
            catch_response=True,
            name="List Blobs"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to list blobs: {response.status_code}")
    
    def delete_blob(self):
        """Delete a blob."""
        with self.client.delete(
            f"/api/stores/{self.store_id}/records/{self.record_id}/blobs/{self.blob_id}",
            catch_response=True,
            name="Delete Blob"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete blob: {response.status_code}")
    
    def delete_record(self):
        """Delete the record."""
        with self.client.delete(
            f"/api/stores/{self.store_id}/records/{self.record_id}",
            catch_response=True,
            name="Delete Record after Blobs"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete record after blobs: {response.status_code}")
    
    def delete_store(self):
        """Delete the store."""
        with self.client.delete(
            f"/api/stores/{self.store_id}",
            catch_response=True,
            name="Delete Store after Blobs"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete store after blobs: {response.status_code}")


class MetadataOperations(TaskSet):
    """Tasks for metadata operations."""
    
    def on_start(self):
        """Initialize metadata operations."""
        self.metadata_id = generate_random_id("meta-")
        self.create_metadata()
    
    def on_stop(self):
        """Clean up after metadata operations."""
        if hasattr(self, 'metadata_created') and self.metadata_created:
            self.delete_metadata()
    
    def create_metadata(self):
        """Create metadata."""
        metadata = {
            "version": f"1.0.{random.randint(0, 100)}",
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "properties": {
                "key1": f"value-{random.randint(1, 1000)}",
                "key2": random.choice([True, False]),
                "key3": random.randint(1, 100)
            }
        }
        
        with self.client.post(
            f"/api/metadata/{self.metadata_id}",
            json=metadata,
            catch_response=True,
            name="Create Metadata"
        ) as response:
            if response.status_code == 200:
                self.metadata_created = True
            else:
                self.metadata_created = False
                response.failure(f"Failed to create metadata: {response.status_code}")
    
    @task(5)
    def get_metadata(self):
        """Get metadata."""
        if not hasattr(self, 'metadata_created') or not self.metadata_created:
            return
            
        with self.client.get(
            f"/api/metadata/{self.metadata_id}",
            catch_response=True,
            name="Get Metadata"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to get metadata: {response.status_code}")
    
    @task(2)
    def update_metadata(self):
        """Update metadata."""
        if not hasattr(self, 'metadata_created') or not self.metadata_created:
            return
            
        metadata = {
            "version": f"1.0.{random.randint(0, 100)}",
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "properties": {
                "key1": f"updated-value-{random.randint(1, 1000)}",
                "key2": random.choice([True, False]),
                "key3": random.randint(1, 100)
            }
        }
        
        with self.client.put(
            f"/api/metadata/{self.metadata_id}",
            json=metadata,
            catch_response=True,
            name="Update Metadata"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Failed to update metadata: {response.status_code}")
    
    def delete_metadata(self):
        """Delete metadata."""
        with self.client.delete(
            f"/api/metadata/{self.metadata_id}",
            catch_response=True,
            name="Delete Metadata"
        ) as response:
            if response.status_code != 204:
                response.failure(f"Failed to delete metadata: {response.status_code}")


class OpenSavesUser(HttpUser):
    """User class for Open Saves load testing."""
    
    wait_time = between(1, 3)
    
    tasks = {
        StoreOperations: 1,
        RecordOperations: 3,
        BlobOperations: 2,
        MetadataOperations: 1
    }
    
    def on_start(self):
        """Initialize the user."""
        # Load configuration if needed
        pass


if __name__ == "__main__":
    # This block is executed when running the script directly
    # It can be used for local testing or configuration
    pass
