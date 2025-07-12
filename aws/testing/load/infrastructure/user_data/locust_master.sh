#!/bin/bash

# Update system
yum update -y
yum install -y python3 python3-pip git amazon-efs-utils

# Install Locust and dependencies
pip3 install locust boto3 matplotlib pandas

# Create directory for Locust files
mkdir -p /locust

# Clone the repository
git clone https://github.com/timjbruce/open-saves-aws.git /tmp/open-saves-aws

# Copy Locust files
cp -r /tmp/open-saves-aws/aws/testing/load/locust/* /locust/

# Mount EFS
mkdir -p /mnt/efs
mount -t efs $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).fs-$(aws efs describe-file-systems --query "FileSystems[?CreationToken=='open-saves-locust-scripts'].FileSystemId" --output text).efs.${region}.amazonaws.com:/ /mnt/efs

# Copy Locust files to EFS
cp -r /locust/* /mnt/efs/

# Create a systemd service for Locust
cat > /etc/systemd/system/locust.service << EOF
[Unit]
Description=Locust Load Testing
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/locust
Environment=PYTHONPATH=/locust
Environment=LOCUST_HOST=${open_saves_url}
ExecStart=/usr/bin/python3 -m locust --master
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable locust
systemctl start locust

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "metrics": {
    "namespace": "OpenSavesLoadTest",
    "metrics_collected": {
      "cpu": {
        "resources": [
          "*"
        ],
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/locust.log",
            "log_group_name": "open-saves-locust-master",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Create a script to run load tests
cat > /locust/run_test.sh << EOF
#!/bin/bash

# Usage: ./run_test.sh <users> <spawn_rate> <run_time>
# Example: ./run_test.sh 100 10 300

USERS=\${1:-100}
SPAWN_RATE=\${2:-10}
RUN_TIME=\${3:-300}

echo "Starting load test with \$USERS users, spawn rate \$SPAWN_RATE, run time \$RUN_TIME seconds"

# Run headless test
locust --master --headless -f /locust/locustfile.py --host=${open_saves_url} --users \$USERS --spawn-rate \$SPAWN_RATE --run-time \${RUN_TIME}s --csv /locust/results_\$USERS

# Process results
python3 /locust/process_results.py --input-file /locust/results_\${USERS}_stats.csv --output-dir /locust/reports/\$USERS

echo "Test completed. Results saved to /locust/reports/\$USERS/"
EOF

chmod +x /locust/run_test.sh

# Create a simple results processor
cat > /locust/process_results.py << EOF
#!/usr/bin/env python3

import argparse
import os
import pandas as pd
import matplotlib.pyplot as plt
import json

def process_results(input_file, output_dir):
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Load the CSV data
    df = pd.read_csv(input_file)
    
    # Calculate summary statistics
    summary = {
        'total_requests': df['Request Count'].sum(),
        'total_failures': df['Failure Count'].sum(),
        'failure_rate': (df['Failure Count'].sum() / df['Request Count'].sum()) * 100 if df['Request Count'].sum() > 0 else 0,
        'median_response_time': df['Median Response Time'].mean(),
        'avg_response_time': df['Average Response Time'].mean(),
        'min_response_time': df['Min Response Time'].min(),
        'max_response_time': df['Max Response Time'].max(),
        'p95_response_time': df['95%'].mean(),
        'requests_per_second': df['Requests/s'].sum()
    }
    
    # Save summary as JSON
    with open(os.path.join(output_dir, 'summary.json'), 'w') as f:
        json.dump(summary, f, indent=2)
    
    # Create plots
    plt.figure(figsize=(12, 8))
    
    # Response time by endpoint
    plt.subplot(2, 2, 1)
    df.sort_values('Average Response Time', ascending=False).plot.bar(x='Name', y='Average Response Time', ax=plt.gca())
    plt.title('Average Response Time by Endpoint')
    plt.xticks(rotation=90)
    plt.tight_layout()
    
    # Request count by endpoint
    plt.subplot(2, 2, 2)
    df.sort_values('Request Count', ascending=False).plot.bar(x='Name', y='Request Count', ax=plt.gca())
    plt.title('Request Count by Endpoint')
    plt.xticks(rotation=90)
    plt.tight_layout()
    
    # Failure count by endpoint
    plt.subplot(2, 2, 3)
    df.sort_values('Failure Count', ascending=False).plot.bar(x='Name', y='Failure Count', ax=plt.gca())
    plt.title('Failure Count by Endpoint')
    plt.xticks(rotation=90)
    plt.tight_layout()
    
    # Response time percentiles
    plt.subplot(2, 2, 4)
    df_melted = pd.melt(df, id_vars=['Name'], value_vars=['Median Response Time', '95%', '99%'], 
                        var_name='Percentile', value_name='Response Time (ms)')
    df_pivot = df_melted.pivot(index='Name', columns='Percentile', values='Response Time (ms)')
    df_pivot.plot.bar(ax=plt.gca())
    plt.title('Response Time Percentiles by Endpoint')
    plt.xticks(rotation=90)
    plt.tight_layout()
    
    # Save the figure
    plt.savefig(os.path.join(output_dir, 'results.png'), dpi=300, bbox_inches='tight')
    
    print(f"Results processed and saved to {output_dir}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process Locust test results')
    parser.add_argument('--input-file', required=True, help='Input CSV file with Locust stats')
    parser.add_argument('--output-dir', required=True, help='Output directory for processed results')
    
    args = parser.parse_args()
    process_results(args.input_file, args.output_dir)
EOF

chmod +x /locust/process_results.py

# Create a script to run all load tests
cat > /locust/run_all_tests.sh << EOF
#!/bin/bash

# Run tests with increasing load
./run_test.sh 100 10 300
./run_test.sh 500 20 300
./run_test.sh 1000 50 300
./run_test.sh 5000 100 300

# Combine results
python3 - << 'PYTHON_SCRIPT'
import os
import json
import pandas as pd

results = []
for users in [100, 500, 1000, 5000]:
    summary_file = f"/locust/reports/{users}/summary.json"
    if os.path.exists(summary_file):
        with open(summary_file, 'r') as f:
            summary = json.load(f)
            summary['users'] = users
            results.append(summary)

if results:
    df = pd.DataFrame(results)
    df.to_csv("/locust/reports/combined_results.csv", index=False)
    
    # Create comparison chart
    import matplotlib.pyplot as plt
    
    plt.figure(figsize=(12, 8))
    
    # RPS vs Users
    plt.subplot(2, 2, 1)
    plt.plot(df['users'], df['requests_per_second'], marker='o')
    plt.title('Requests per Second vs Users')
    plt.xlabel('Number of Users')
    plt.ylabel('Requests per Second')
    plt.grid(True)
    
    # Response Time vs Users
    plt.subplot(2, 2, 2)
    plt.plot(df['users'], df['avg_response_time'], marker='o', label='Average')
    plt.plot(df['users'], df['median_response_time'], marker='s', label='Median')
    plt.plot(df['users'], df['p95_response_time'], marker='^', label='95th Percentile')
    plt.title('Response Time vs Users')
    plt.xlabel('Number of Users')
    plt.ylabel('Response Time (ms)')
    plt.legend()
    plt.grid(True)
    
    # Failure Rate vs Users
    plt.subplot(2, 2, 3)
    plt.plot(df['users'], df['failure_rate'], marker='o')
    plt.title('Failure Rate vs Users')
    plt.xlabel('Number of Users')
    plt.ylabel('Failure Rate (%)')
    plt.grid(True)
    
    # Save the figure
    plt.tight_layout()
    plt.savefig("/locust/reports/comparison.png", dpi=300, bbox_inches='tight')
PYTHON_SCRIPT

echo "All tests completed. Combined results saved to /locust/reports/"
EOF

chmod +x /locust/run_all_tests.sh

# Create reports directory
mkdir -p /locust/reports

echo "Locust master setup complete"
