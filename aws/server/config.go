package server

import (
	"fmt"
	"io/ioutil"
	"os"

	"gopkg.in/yaml.v2"
)

// Config represents the server configuration
type Config struct {
	Server struct {
		HTTPPort int `yaml:"http_port"`
		GRPCPort int `yaml:"grpc_port"`
	} `yaml:"server"`
	AWS struct {
		Region      string `yaml:"region"`
		DynamoDB    struct {
			StoresTable   string `yaml:"stores_table"`
			RecordsTable  string `yaml:"records_table"`
			MetadataTable string `yaml:"metadata_table"`
		} `yaml:"dynamodb"`
		S3          struct {
			BucketName string `yaml:"bucket_name"`
		} `yaml:"s3"`
		ElastiCache struct {
			Address string `yaml:"address"`
			TTL     int    `yaml:"ttl"`
		} `yaml:"elasticache"`
	} `yaml:"aws"`
}

// LoadConfig loads the configuration from a file
func LoadConfig(path string) (*Config, error) {
	// Check if the file exists
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, fmt.Errorf("config file not found: %s", path)
	}

	// Read the file
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %v", err)
	}

	// Parse the YAML
	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %v", err)
	}

	// Set defaults
	if config.Server.HTTPPort == 0 {
		config.Server.HTTPPort = 8080
	}
	if config.Server.GRPCPort == 0 {
		config.Server.GRPCPort = 8081
	}
	if config.AWS.Region == "" {
		config.AWS.Region = "us-west-2"
	}
	if config.AWS.DynamoDB.StoresTable == "" {
		config.AWS.DynamoDB.StoresTable = "open-saves-stores"
	}
	if config.AWS.DynamoDB.RecordsTable == "" {
		config.AWS.DynamoDB.RecordsTable = "open-saves-records"
	}
	if config.AWS.DynamoDB.MetadataTable == "" {
		config.AWS.DynamoDB.MetadataTable = "open-saves-metadata"
	}
	if config.AWS.S3.BucketName == "" {
		config.AWS.S3.BucketName = "open-saves-blobs"
	}
	if config.AWS.ElastiCache.TTL == 0 {
		config.AWS.ElastiCache.TTL = 3600
	}

	return &config, nil
}
