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

# Start Locust master
cd /opt/locust
nohup locust -f locustfile.py --master --host=${ENDPOINT} --web-host=0.0.0.0 > /var/log/locust-master.log 2>&1 &

# Wait for Locust to start
sleep 5

# Print the Locust master URL
echo "Locust master is running at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8089"
