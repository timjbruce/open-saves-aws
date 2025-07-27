#!/bin/bash
set -e

# Install required packages
yum update -y
yum install -y python3 python3-pip git

# Downgrade urllib3 to avoid OpenSSL compatibility issues
pip3 install urllib3==1.26.15

# Install Locust
pip3 install locust

# Create directory for Locust files
mkdir -p /opt/locust

# Copy locustfile from S3
aws s3 cp s3://${BUCKET_NAME}/locustfile.py /opt/locust/locustfile.py

# Ensure ENDPOINT has http:// or https:// prefix
if [[ ! "${ENDPOINT}" =~ ^https?:// ]]; then
  ENDPOINT="https://${ENDPOINT}"
fi

# Start Locust worker
cd /opt/locust
nohup locust -f locustfile.py --worker --master-host=${MASTER_HOST} --host=${ENDPOINT} > /var/log/locust-worker.log 2>&1 &

# Print confirmation
echo "Locust worker started and connected to master at ${MASTER_HOST}"
