import time
import json
import random
import string
import base64
import urllib.parse
import re
from locust import HttpUser, task, between, events

game_ids = ["game_1", "game_2", "game_3", "game_4", "game_5"]

# Constants for continuous operation
MAX_RECORDS_PER_STORE = 50  # Limit records per store to avoid excessive memory usage
MIN_RECORDS_BEFORE_DELETE = 10  # Minimum records to keep before deleting
CLEANUP_PROBABILITY = 0.1  # 10% chance to clean up old records when we reach the limit

# Define simplified API endpoint templates for the Locust UI
API_TEMPLATES = {
    "create_store": "/api/stores",
    "get_store": "/api/stores/{store_id}",
    "list_records": "/api/stores/{store_id}/records",
    "create_record": "/api/stores/{store_id}/records",
    "get_record": "/api/stores/{store_id}/records/{record_id}",
    "update_record": "/api/stores/{store_id}/records/{record_id}",
    "create_blob": "/api/stores/{store_id}/records/{record_id}/blobs/{blob_id}",
    "get_blob": "/api/stores/{store_id}/records/{record_id}/blobs/{blob_id}",
    "update_blob": "/api/stores/{store_id}/records/{record_id}/blobs/{blob_id}",
    "query_by_owner": "/api/stores/{store_id}/records?owner_id={owner_id}",
    "query_by_game": "/api/stores/{store_id}/records?game_id={game_id}"
}

# Event hook to modify request names in the Locust UI
@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, **kwargs):
    # Extract the base path from the URL
    url_parts = name.split('?')[0].split('/')
    
    # Simplify the request name based on the URL pattern
    if len(url_parts) >= 3 and url_parts[1] == "api" and url_parts[2] == "stores":
        # Store operations
        if len(url_parts) == 3:
            if request_type == "POST":
                return "POST " + API_TEMPLATES["create_store"]
            else:
                return request_type + " " + API_TEMPLATES["get_store"]
        
        # Record operations
        elif len(url_parts) == 5 and url_parts[4] == "records":
            if request_type == "GET":
                if "?" in name:
                    if "owner_id" in name:
                        return "GET " + API_TEMPLATES["query_by_owner"]
                    elif "game_id" in name:
                        return "GET " + API_TEMPLATES["query_by_game"]
                return "GET " + API_TEMPLATES["list_records"]
            elif request_type == "POST":
                return "POST " + API_TEMPLATES["create_record"]
        
        # Individual record operations
        elif len(url_parts) == 6:
            if request_type == "GET":
                return "GET " + API_TEMPLATES["get_record"]
            elif request_type == "PUT":
                return "PUT " + API_TEMPLATES["update_record"]
        
        # Blob operations
        elif len(url_parts) >= 8 and url_parts[6] == "blobs":
            if request_type == "PUT":
                return "PUT " + API_TEMPLATES["create_blob"]
            elif request_type == "GET":
                return "GET " + API_TEMPLATES["get_blob"]

def random_string(length=10):
    """Generate a random string of fixed length and URL-encode it."""
    letters = string.ascii_lowercase
    raw_string = ''.join(random.choice(letters) for i in range(length))
    # URL-encode the string to ensure it's safe for use in URLs
    return urllib.parse.quote(raw_string)


def game_id():
    """return a game id from a list of game ids"""
    return random.choice(game_ids)


def generate_large_text(size_kb=32):
    """Generate a random text of specified size in KB."""
    # 1 KB is approximately 1024 characters
    size_chars = size_kb * 1024
    return random_string(size_chars)


def log_error(response, operation, payload=None):
    """Log error details including URI and request data."""
    # Get the calling method name
    import inspect
    caller_frame = inspect.currentframe().f_back
    caller_method = inspect.getframeinfo(caller_frame).function
    
    error_msg = f"ERROR: {operation} failed with status {response.status_code}"
    error_msg += f"\n  Python Method: {caller_method}"
    error_msg += f"\n  Method: {response.request.method}"
    error_msg += f"\n  URI: {response.request.url}"
    
    if payload:
        try:
            # Truncate payload if it's too large
            payload_str = str(payload)
            if len(payload_str) > 500:
                payload_str = payload_str[:500] + "... [truncated]"
            error_msg += f"\n  Request data: {payload_str}"
        except:
            error_msg += "\n  Request data: [Could not serialize payload]"
    
    try:
        error_msg += f"\n  Response: {response.text[:500]}"
        if len(response.text) > 500:
            error_msg += "... [truncated]"
    except:
        error_msg += "\n  Response: [Could not get response text]"
    
    print(error_msg)


def log_api_call(response, operation, payload=None):
    """Log API call with placeholder values for variable data."""
    # Get the calling method name
    import inspect
    caller_frame = inspect.currentframe().f_back
    caller_method = inspect.getframeinfo(caller_frame).function
    
    # Create a template URL by replacing variable parts with placeholders
    url = response.request.url
    # Replace UUIDs, record IDs, store IDs, etc. with placeholders
    template_url = re.sub(r'[a-zA-Z0-9_-]+_load_test_store', '{store_id}', url)
    template_url = re.sub(r'record_[a-zA-Z0-9_-]+', '{record_id}', template_url)
    template_url = re.sub(r'blob_record_[a-zA-Z0-9_-]+', '{blob_record_id}', template_url)
    template_url = re.sub(r'blob_[a-zA-Z0-9_-]+', '{blob_id}', template_url)
    
    log_msg = f"API CALL: {operation} - Status: {response.status_code}"
    log_msg += f"\n  Python Method: {caller_method}"
    log_msg += f"\n  Method: {response.request.method}"
    log_msg += f"\n  Template URI: {template_url}"
    
    if payload:
        try:
            # Create a template payload by replacing variable values with placeholders
            if isinstance(payload, dict):
                template_payload = {}
                for key, value in payload.items():
                    if key == "record_id":
                        template_payload[key] = "{record_id}"
                    elif key == "store_id":
                        template_payload[key] = "{store_id}"
                    elif key == "owner_id":
                        template_payload[key] = "{owner_id}"
                    elif key == "game_id":
                        template_payload[key] = "{game_id}"
                    elif key == "blob":
                        template_payload[key] = "{blob_data}"
                    elif key == "properties" and isinstance(value, dict):
                        template_payload[key] = {}
                        for prop_key, prop_value in value.items():
                            if isinstance(prop_value, dict) and "string_value" in prop_value:
                                prop_value["string_value"] = "{string_value}"
                            if isinstance(prop_value, dict) and "integer_value" in prop_value:
                                prop_value["integer_value"] = "{integer_value}"
                            template_payload[key][prop_key] = prop_value
                    else:
                        template_payload[key] = value
                
                log_msg += f"\n  Template Payload: {json.dumps(template_payload, indent=2)}"
            else:
                log_msg += f"\n  Payload Type: {type(payload).__name__}"
                if isinstance(payload, str) and len(payload) > 100:
                    log_msg += f"\n  Payload Size: {len(payload)} bytes"
                else:
                    log_msg += f"\n  Payload: {payload}"
        except Exception as e:
            log_msg += f"\n  Payload: [Could not template payload: {str(e)}]"
    
    # For successful responses, include a sample of the response
    if 200 <= response.status_code < 300:
        try:
            if response.headers.get('Content-Type', '').startswith('application/json'):
                response_json = response.json()
                # Replace variable values in the response with placeholders
                template_response = {}
                if isinstance(response_json, dict):
                    for key, value in response_json.items():
                        if key == "record_id":
                            template_response[key] = "{record_id}"
                        elif key == "store_id":
                            template_response[key] = "{store_id}"
                        elif key == "owner_id":
                            template_response[key] = "{owner_id}"
                        elif key == "records" and isinstance(value, list):
                            template_response[key] = "[{record_objects}]"
                        else:
                            template_response[key] = value
                    
                    log_msg += f"\n  Template Response: {json.dumps(template_response, indent=2)[:500]}"
                else:
                    log_msg += f"\n  Response Type: {type(response_json).__name__}"
            elif response.headers.get('Content-Type', '').startswith('application/octet-stream'):
                log_msg += f"\n  Response: Binary data of size {len(response.content)} bytes"
            else:
                if len(response.text) > 100:
                    log_msg += f"\n  Response: Text data of size {len(response.text)} bytes"
                else:
                    log_msg += f"\n  Response: {response.text}"
        except:
            log_msg += "\n  Response: [Could not process response]"
    
    print(log_msg)


class OpenSavesUser(HttpUser):
    wait_time = between(1, 3)
    
    def on_start(self):
        """Initialize user with a store."""
        self.store_key = f"{random_string()}_load_test_store"
        self.owner_id = f"{random_string(8)}_owner"
        self.create_store()
        # Initialize record tracking
        self.record_keys = []
        self.blob_record_keys = []
        # Track creation time for records to enable age-based cleanup
        self.record_creation_times = {}
        # Add counters for record creation and verification
        self.records_created_count = 0
        self.records_with_blobs_count = 0
        self.last_server_record_count = 0
        self.last_verification_time = time.time()
    
    def on_stop(self):
        """Clean up by deleting the store."""
        # Commented out to prevent deletion of stores during testing
        # self.delete_store()
        pass
    
    def create_store(self):
        """Create a new store."""
        payload = {
            "store_id": self.store_key,
            "name": f"Load Test Store {random_string()}",
            "owner_id": self.owner_id
        }
        # Save the original payload for later verification
        self.store_payload = payload.copy()
        
        response = self.client.post("/api/stores", json=payload, name="POST /api/stores")
        if 200 <= response.status_code < 300:
            self.store_id = self.store_key
            log_api_call(response, "Create store", payload)
        else:
            self.store_id = None
            log_error(response, "Create store", payload)
    
    def delete_store(self):
        """Delete the store."""
        # Commented out to prevent deletion of stores during testing
        # if hasattr(self, 'store_id') and self.store_id:
        #     response = self.client.delete(f"/api/stores/{self.store_id}")
        #     if not (200 <= response.status_code < 300):
        #         log_error(response, f"Delete store {self.store_id}")
        pass
    
    def manage_record_count(self):
        """Manage the number of records to prevent excessive growth."""
        # Commented out to prevent deletion of records during testing
        # # If we have too many records, consider cleaning up
        # if len(self.record_keys) > MAX_RECORDS_PER_STORE and random.random() < CLEANUP_PROBABILITY:
        #     # Keep track of how many records to delete
        #     records_to_delete = len(self.record_keys) - MIN_RECORDS_BEFORE_DELETE
        #     
        #     # Sort records by age (oldest first) if we have creation times
        #     if self.record_creation_times:
        #         sorted_records = sorted(
        #             self.record_keys,
        #             key=lambda k: self.record_creation_times.get(k, float('inf'))
        #         )
        #         
        #         # Delete the oldest records
        #         for i in range(min(records_to_delete, len(sorted_records))):
        #             self.delete_specific_record(sorted_records[i])
        pass
    
    def delete_specific_record(self, record_key):
        """Delete a specific record by key."""
        # Commented out to prevent deletion of records during testing
        # if record_key in self.record_keys:
        #     response = self.client.delete(f"/api/stores/{self.store_id}/records/{record_key}")
        #     if 200 <= response.status_code < 300:
        #         self.record_keys.remove(record_key)
        #         # Also remove from blob_record_keys if it exists there
        #         if record_key in self.blob_record_keys:
        #             self.blob_record_keys.remove(record_key)
        #         # Remove from creation times tracking
        #         if record_key in self.record_creation_times:
        #             del self.record_creation_times[record_key]
        #     else:
        #         log_error(response, f"Delete specific record {record_key}")
        pass
    
    @task(5)
    def create_record(self):
        """Create a new record in the store."""
        if not hasattr(self, 'store_id') or not self.store_id:
            return
        
        # Manage record count before creating new ones
        self.manage_record_count()
        
        record_key = f"{random_string()}_record"
        payload = {
            "record_id": record_key,
            "properties": {
                "test_prop_1": {"type": "STRING", "string_value": random_string(5)},
                "test_prop_2": {"type": "INTEGER", "integer_value": random.randint(1, 1000)},
                "owner_id": self.owner_id,
                "game_id": game_id()
            }
        }
        response = self.client.post(
            f"/api/stores/{self.store_id}/records", 
            json=payload,
            name="POST /api/stores/{store_id}/records"
        )
        if 200 <= response.status_code < 300:
            # Add the new record key to our list
            self.record_keys.append(record_key)
            # Track creation time
            self.record_creation_times[record_key] = time.time()
            # Increment the record counter
            self.records_created_count += 1
            log_api_call(response, "Create record", payload)
        else:
            log_error(response, f"Create record {record_key}", payload)
    
    @task(4)
    def create_record_with_blob(self):
        """Create a new record with a 32KB blob in the store."""
        if not hasattr(self, 'store_id') or not self.store_id:
            return
        
        # Manage record count before creating new ones
        self.manage_record_count()
        
        record_key = f"{random_string()}_blob_record"
        blob_id = f"{random_string()}_blob"
        
        # Step 1: Create a regular record first
        record_payload = {
            "record_id": record_key,
            "properties": {
                "test_prop_1": {"type": "STRING", "string_value": random_string(5)},
                "test_prop_2": {"type": "INTEGER", "integer_value": random.randint(1, 1000)},
                "owner_id": self.owner_id,
                "game_id": game_id()
            }
        }
        
        record_response = self.client.post(
            f"/api/stores/{self.store_id}/records", 
            json=record_payload,
            name="POST /api/stores/{store_id}/records"
        )
        if not (200 <= record_response.status_code < 300):
            log_error(record_response, f"Create record for blob {record_key}", record_payload)
            return
        
        log_api_call(record_response, "Create record for blob", record_payload)
            
        # Step 2: Generate blob data and upload it
        # Generate 32KB of text data
        blob_data = generate_large_text(32)
        
        # Convert text to binary
        binary_data = blob_data.encode('utf-8')
        
        # Send the binary data with the correct content type header
        headers = {"Content-Type": "application/octet-stream"}
        blob_response = self.client.put(
            f"/api/stores/{self.store_id}/records/{record_key}/blobs/{blob_id}", 
            data=binary_data,  # Use data instead of json for binary content
            headers=headers,
            name="PUT /api/stores/{store_id}/records/{record_id}/blobs/{blob_id}"
        )
        
        if 200 <= blob_response.status_code < 300:
            # Add the new record key to our lists
            self.record_keys.append(record_key)
            self.blob_record_keys.append(record_key)
            # Track creation time
            self.record_creation_times[record_key] = time.time()
            # Increment both counters
            self.records_created_count += 1
            self.records_with_blobs_count += 1
            log_api_call(blob_response, f"Upload blob for record {record_key}", f"Binary data of size {len(binary_data)} bytes")
        else:
            log_error(blob_response, f"Upload blob for record {record_key}", f"Binary data of size {len(binary_data)} bytes")
    
    @task(3)
    def get_blob_record(self):
        """Get a record with blob from the store."""
        if not hasattr(self, 'store_id') or not self.store_id or not self.blob_record_keys:
            return
        
        if self.blob_record_keys:
            record_key = random.choice(self.blob_record_keys)
            
            # Step 1: Get the record metadata first
            metadata_response = self.client.get(
                f"/api/stores/{self.store_id}/records/{record_key}",
                name="GET /api/stores/{store_id}/records/{record_id}"
            )
            
            if not (200 <= metadata_response.status_code < 300):
                log_error(metadata_response, f"Get record metadata for blob {record_key}")
                # If record not found, remove it from our tracking
                if metadata_response.status_code == 404:
                    self.blob_record_keys.remove(record_key)
                    if record_key in self.record_keys:
                        self.record_keys.remove(record_key)
                    if record_key in self.record_creation_times:
                        del self.record_creation_times[record_key]
                return
            
            log_api_call(metadata_response, f"Get record metadata for blob", None)
            
            try:
                # Parse the response to get the blob keys
                record_data = metadata_response.json()
                blob_keys = record_data.get("blob_keys", [])
                
                # Look for "blob1" in the blob_keys list
                blob_id = None
                for key in blob_keys:
                    if key == "blob1" or "blob" in key:  # Look for blob1 or any blob key
                        blob_id = key
                        break
                
                # If no blob key was found, use the record key as fallback
                if not blob_id:
                    # Try the first blob key if available
                    if blob_keys:
                        blob_id = blob_keys[0]
                    else:
                        # Last resort: use the record key itself
                        blob_id = record_key
                
                # Step 2: Get the actual blob using the blob_id
                blob_response = self.client.get(
                    f"/api/stores/{self.store_id}/records/{record_key}/blobs/{blob_id}",
                    headers={"Accept": "application/octet-stream"},
                    name="GET /api/stores/{store_id}/records/{record_id}/blobs/{blob_id}"
                )
                
                if 200 <= blob_response.status_code < 300:
                    log_api_call(blob_response, f"Get blob {blob_id} for record", None)
                else:
                    log_error(blob_response, f"Get blob {blob_id} for record {record_key}")
            
            except Exception as e:
                print(f"Error processing record metadata for blob retrieval: {e}")
    
    @task(2)
    def update_record_with_blob(self):
        """Update a record with a new 32KB blob."""
        if not hasattr(self, 'store_id') or not self.store_id or not self.blob_record_keys:
            return
        
        if self.blob_record_keys:
            record_key = random.choice(self.blob_record_keys)
            blob_id = f"blob_{random_string()}"  # Generate a new blob ID for the update
            
            # Generate new 32KB of text data
            blob_data = generate_large_text(32)
            
            # Convert text to binary
            binary_data = blob_data.encode('utf-8')
            
            # Send the binary data with the correct content type header
            headers = {"Content-Type": "application/octet-stream"}
            response = self.client.put(
                f"/api/stores/{self.store_id}/records/{record_key}/blobs/{blob_id}", 
                data=binary_data,  # Use data instead of json for binary content
                headers=headers,
                name="PUT /api/stores/{store_id}/records/{record_id}/blobs/{blob_id}"
            )
            
            if 200 <= response.status_code < 300:
                log_api_call(response, f"Update blob for record", f"Binary data of size {len(binary_data)} bytes")
            else:
                log_error(response, f"Update blob for record {record_key}", f"Binary data of size {len(binary_data)} bytes")
                # If record not found, remove it from our tracking
                if response.status_code == 404:
                    self.blob_record_keys.remove(record_key)
                    if record_key in self.record_keys:
                        self.record_keys.remove(record_key)
                    if record_key in self.record_creation_times:
                        del self.record_creation_times[record_key]
    
    @task(10)
    def get_record(self):
        """Get a record from the store."""
        if not hasattr(self, 'store_id') or not self.store_id or not self.record_keys:
            return
        
        if self.record_keys:
            record_key = random.choice(self.record_keys)
            response = self.client.get(
                f"/api/stores/{self.store_id}/records/{record_key}",
                name="GET /api/stores/{store_id}/records/{record_id}"
            )
            if 200 <= response.status_code < 300:
                log_api_call(response, "Get record", None)
            else:
                log_error(response, f"Get record {record_key}")
                # If record not found, remove it from our tracking
                if response.status_code == 404:
                    self.record_keys.remove(record_key)
                    if record_key in self.blob_record_keys:
                        self.blob_record_keys.remove(record_key)
                    if record_key in self.record_creation_times:
                        del self.record_creation_times[record_key]
    
    @task(3)
    def update_record(self):
        """Update a record in the store."""
        if not hasattr(self, 'store_id') or not self.store_id or not self.record_keys:
            return
        
        if self.record_keys:
            record_key = random.choice(self.record_keys)
            payload = {
                "properties": {
                    "updated_prop": {"type": "STRING", "string_value": random_string(5)},
                    "timestamp": {"type": "INTEGER", "integer_value": int(time.time())}
                }
            }
            response = self.client.put(
                f"/api/stores/{self.store_id}/records/{record_key}", 
                json=payload,
                name="PUT /api/stores/{store_id}/records/{record_id}"
            )
            if 200 <= response.status_code < 300:
                log_api_call(response, "Update record", payload)
            else:
                log_error(response, f"Update record {record_key}", payload)
                # If record not found, remove it from our tracking
                if response.status_code == 404:
                    self.record_keys.remove(record_key)
                    if record_key in self.blob_record_keys:
                        self.blob_record_keys.remove(record_key)
                    if record_key in self.record_creation_times:
                        del self.record_creation_times[record_key]
    
    @task(2)
    def delete_record(self):
        """Delete a record from the store."""
        # Commented out to prevent deletion of records during testing
        pass
    
    @task(1)
    def list_records(self):
        """List records in the store."""
        if not hasattr(self, 'store_id') or not self.store_id:
            return
        
        response = self.client.get(
            f"/api/stores/{self.store_id}/records",
            name="GET /api/stores/{store_id}/records"
        )
        if 200 <= response.status_code < 300:
            log_api_call(response, "List records", None)
            try:
                records = response.json().get("records", [])
                server_record_count = len(records)
                self.last_server_record_count = server_record_count
                
                # Verify record count (only check every 30 seconds to avoid too many failures)
                current_time = time.time()
                if current_time - self.last_verification_time > 30:
                    self.last_verification_time = current_time
                    if server_record_count != self.records_created_count:
                        error_message = f"RECORD COUNT MISMATCH: Server has {server_record_count} records, but we've created {self.records_created_count} records"
                        print(error_message)
                        # Fire a failure event to make Locust report this as a failure
                        events.request_failure.fire(
                            request_type="VERIFICATION",
                            name="Record Count Verification",
                            response_time=0,
                            exception=Exception(error_message)
                        )
                    else:
                        print(f"RECORD COUNT VERIFIED: Server has {server_record_count} records, matching our count of {self.records_created_count} created records")
                    
                    # Also verify blob records
                    server_blob_record_count = len([r for r in records if r.get("blob_keys", [])])
                    if server_blob_record_count != self.records_with_blobs_count:
                        error_message = f"BLOB RECORD COUNT MISMATCH: Server has {server_blob_record_count} records with blobs, but we've created {self.records_with_blobs_count}"
                        print(error_message)
                        # Fire a failure event to make Locust report this as a failure
                        events.request_failure.fire(
                            request_type="VERIFICATION",
                            name="Blob Record Count Verification",
                            response_time=0,
                            exception=Exception(error_message)
                        )
                    else:
                        print(f"BLOB RECORD COUNT VERIFIED: Server has {server_blob_record_count} records with blobs, matching our count of {self.records_with_blobs_count}")
                
                # Update our tracking with the actual state from the server
                server_record_ids = [record.get("record_id") for record in records]
                
                # Update blob_record_keys based on records that have blobs
                server_blob_record_ids = [record.get("record_id") for record in records if record.get("blob_keys", [])]
                
                # Sync our local tracking with server state
                # Keep only records that exist on the server
                self.record_keys = [key for key in self.record_keys if key in server_record_ids]
                self.blob_record_keys = [key for key in self.blob_record_keys if key in server_blob_record_ids]
                
                # Add any records from server that we don't know about
                for record_id in server_record_ids:
                    if record_id not in self.record_keys:
                        self.record_keys.append(record_id)
                        # Set creation time to now for newly discovered records
                        self.record_creation_times[record_id] = time.time()
                
                # Update blob records
                for record_id in server_blob_record_ids:
                    if record_id not in self.blob_record_keys:
                        self.blob_record_keys.append(record_id)
                
            except Exception as e:
                print(f"Failed to parse list records response: {e}")
        else:
            log_error(response, f"List records for store {self.store_id}")
    
    @task(1)
    def get_store(self):
        """Get store details."""
        if not hasattr(self, 'store_id') or not self.store_id:
            return
        
        response = self.client.get(
            f"/api/stores/{self.store_id}",
            name="GET /api/stores/{store_id}"
        )
        if 200 <= response.status_code < 300:
            log_api_call(response, "Get store", None)
            
            # Verify store details match what was sent
            try:
                store_data = response.json()
                mismatches = []
                
                # Check store_id
                if store_data.get("store_id") != self.store_payload.get("store_id"):
                    mismatches.append(f"store_id: expected '{self.store_payload.get('store_id')}', got '{store_data.get('store_id')}'")
                
                # Check name
                if store_data.get("name") != self.store_payload.get("name"):
                    mismatches.append(f"name: expected '{self.store_payload.get('name')}', got '{store_data.get('name')}'")
                
                # Check owner_id
                if store_data.get("owner_id") != self.store_payload.get("owner_id"):
                    mismatches.append(f"owner_id: expected '{self.store_payload.get('owner_id')}', got '{store_data.get('owner_id')}'")
                
                # If there are any mismatches, report a failure
                if mismatches:
                    error_message = f"STORE DETAILS MISMATCH: {', '.join(mismatches)}"
                    print(error_message)
                    # Fire a failure event to make Locust report this as a failure
                    events.request_failure.fire(
                        request_type="VERIFICATION",
                        name="Store Details Verification",
                        response_time=0,
                        exception=Exception(error_message)
                    )
            except Exception as e:
                error_message = f"Failed to verify store details: {str(e)}"
                print(error_message)
                events.request_failure.fire(
                    request_type="VERIFICATION",
                    name="Store Details Verification",
                    response_time=0,
                    exception=Exception(error_message)
                )
        else:
            log_error(response, f"Get store {self.store_id}")
    
    @task(3)
    def query_records_by_owner(self):
        """Query records by owner_id."""
        if not hasattr(self, 'store_id') or not self.store_id or not hasattr(self, 'owner_id'):
            return
        
        response = self.client.get(
            f"/api/stores/{self.store_id}/records?owner_id={self.owner_id}",
            name="GET /api/stores/{store_id}/records?owner_id={owner_id}"
        )
        if 200 <= response.status_code < 300:
            log_api_call(response, "Query records by owner", None)
            
            # Verify all returned records have the correct owner_id
            try:
                records = response.json().get("records", [])
                mismatched_records = []
                
                for record in records:
                    if record.get("owner_id") != self.owner_id:
                        mismatched_records.append(f"Record {record.get('record_id')} has owner_id '{record.get('owner_id')}' instead of '{self.owner_id}'")
                
                if mismatched_records:
                    error_message = f"OWNER_ID QUERY MISMATCH: {len(mismatched_records)} out of {len(records)} records have incorrect owner_id\n" + "\n".join(mismatched_records[:5])
                    if len(mismatched_records) > 5:
                        error_message += f"\n... and {len(mismatched_records) - 5} more"
                    print(error_message)
                    # Fire a failure event to make Locust report this as a failure
                    events.request_failure.fire(
                        request_type="VERIFICATION",
                        name="Owner ID Query Verification",
                        response_time=0,
                        exception=Exception(error_message)
                    )
            except Exception as e:
                error_message = f"Failed to verify owner_id query results: {str(e)}"
                print(error_message)
                events.request_failure.fire(
                    request_type="VERIFICATION",
                    name="Owner ID Query Verification",
                    response_time=0,
                    exception=Exception(error_message)
                )
        else:
            log_error(response, f"Query records by owner {self.owner_id}")
    
    @task(3)
    def query_records_by_game(self):
        """Query records by game_id."""
        if not hasattr(self, 'store_id') or not self.store_id:
            return
        
        selected_game_id = game_id()
        response = self.client.get(
            f"/api/stores/{self.store_id}/records?game_id={selected_game_id}",
            name="GET /api/stores/{store_id}/records?game_id={game_id}"
        )
        if 200 <= response.status_code < 300:
            log_api_call(response, "Query records by game", None)
            
            # Verify all returned records have the correct game_id
            try:
                records = response.json().get("records", [])
                mismatched_records = []
                
                for record in records:
                    if record.get("game_id") != selected_game_id:
                        mismatched_records.append(f"Record {record.get('record_id')} has game_id '{record.get('game_id')}' instead of '{selected_game_id}'")
                
                if mismatched_records:
                    error_message = f"GAME_ID QUERY MISMATCH: {len(mismatched_records)} out of {len(records)} records have incorrect game_id\n" + "\n".join(mismatched_records[:5])
                    if len(mismatched_records) > 5:
                        error_message += f"\n... and {len(mismatched_records) - 5} more"
                    print(error_message)
                    # Fire a failure event to make Locust report this as a failure
                    events.request_failure.fire(
                        request_type="VERIFICATION",
                        name="Game ID Query Verification",
                        response_time=0,
                        exception=Exception(error_message)
                    )
            except Exception as e:
                error_message = f"Failed to verify game_id query results: {str(e)}"
                print(error_message)
                events.request_failure.fire(
                    request_type="VERIFICATION",
                    name="Game ID Query Verification",
                    response_time=0,
                    exception=Exception(error_message)
                )
        else:
            log_error(response, f"Query records by game {selected_game_id}")
