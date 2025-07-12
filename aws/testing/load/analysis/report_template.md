# Open Saves Load Test Report

## Test Configuration

- **Date:** {{date}}
- **Environment:** {{environment}}
- **Target URL:** {{target_url}}
- **Test Duration:** {{duration}} seconds
- **Users:** {{users}}
- **Spawn Rate:** {{spawn_rate}} users/second

## Summary

- **Total Requests:** {{total_requests}}
- **Total Failures:** {{total_failures}}
- **Failure Rate:** {{failure_rate}}%
- **Average Response Time:** {{avg_response_time}} ms
- **Median Response Time:** {{median_response_time}} ms
- **95th Percentile Response Time:** {{p95_response_time}} ms
- **99th Percentile Response Time:** {{p99_response_time}} ms
- **Maximum Response Time:** {{max_response_time}} ms
- **Requests Per Second:** {{total_rps}}

## Endpoint Performance

| Endpoint | Requests | Failures | Failure Rate | Avg Response Time | Median Response Time | 95th Percentile | 99th Percentile | Max Response Time | RPS |
|----------|----------|----------|--------------|-------------------|----------------------|-----------------|-----------------|-------------------|-----|
{{#endpoints}}
| {{name}} | {{request_count}} | {{failure_count}} | {{failure_rate}}% | {{avg_response_time}} ms | {{median_response_time}} ms | {{p95_response_time}} ms | {{p99_response_time}} ms | {{max_response_time}} ms | {{rps}} |
{{/endpoints}}

## Visualizations

### Endpoint Metrics
![Endpoint Metrics](./endpoint_metrics.png)

### Response Time Distribution
![Response Time Distribution](./response_time_distribution.png)

### Time Series Metrics
![Time Series Metrics](./time_series.png)

## System Resource Utilization

### EKS Pod Resources
![EKS Pod Resources](./eks_pod_resources.png)

### DynamoDB Metrics
![DynamoDB Metrics](./dynamodb_metrics.png)

### S3 Metrics
![S3 Metrics](./s3_metrics.png)

### Redis Metrics
![Redis Metrics](./redis_metrics.png)

## Analysis

### Performance Bottlenecks
{{performance_bottlenecks}}

### Scaling Recommendations
{{scaling_recommendations}}

### Cost Implications
{{cost_implications}}

## Conclusion
{{conclusion}}
