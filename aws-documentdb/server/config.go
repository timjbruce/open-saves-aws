package server

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ssm"
	"gopkg.in/yaml.v2"
)

// Config represents the server configuration
type Config struct {
	Server struct {
		HTTPPort int `yaml:"http_port" json:"http_port"`
		GRPCPort int `yaml:"grpc_port" json:"grpc_port"`
	} `yaml:"server" json:"server"`
	AWS struct {
		Region      string `yaml:"region" json:"region"`
		DocumentDB  struct {
			ConnectionString  string `yaml:"connection_string" json:"connection_string"`
			PasswordSecretArn string `yaml:"password_secret_arn" json:"password_secret_arn"`
			DatabaseName      string `yaml:"database_name" json:"database_name"`
		} `yaml:"documentdb" json:"documentdb"`
		S3          struct {
			BucketName string `yaml:"bucket_name" json:"bucket_name"`
		} `yaml:"s3" json:"s3"`
		ElastiCache struct {
			Address string `yaml:"address" json:"address"`
			TTL     int    `yaml:"ttl" json:"ttl"`
		} `yaml:"elasticache" json:"elasticache"`
		ECR struct {
			RepositoryURI string `yaml:"repository_uri" json:"repository_uri"`
		} `yaml:"ecr" json:"ecr"`
	} `yaml:"aws" json:"aws"`
}

// LoadConfig loads the configuration from Parameter Store
func LoadConfig(path string) (*Config, error) {
	fmt.Printf("DEBUG: LoadConfig called with path: %s\n", path)
	fmt.Printf("DEBUG: Loading from Parameter Store\n")
	return loadConfigFromParameterStore(path)
}

// loadConfigFromFile loads the configuration from a YAML file
func loadConfigFromFile(path string) (*Config, error) {
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

	// Apply defaults
	applyDefaults(&config)

	return &config, nil
}

// loadConfigFromParameterStore loads the configuration from AWS Parameter Store
func loadConfigFromParameterStore(paramPath string) (*Config, error) {
	// Create AWS session
	sess, err := session.NewSession()
	if err != nil {
		return nil, fmt.Errorf("failed to create AWS session: %v", err)
	}

	// Create SSM client
	ssmClient := ssm.New(sess)

	// Get parameter from Parameter Store
	param, err := ssmClient.GetParameter(&ssm.GetParameterInput{
		Name:           aws.String(paramPath),
		WithDecryption: aws.Bool(true),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get parameter from Parameter Store: %v", err)
	}

	// Parse the JSON
	var config Config
	if err := json.Unmarshal([]byte(*param.Parameter.Value), &config); err != nil {
		return nil, fmt.Errorf("failed to parse parameter value as JSON: %v", err)
	}

	// Apply defaults
	applyDefaults(&config)

	return &config, nil
}

// applyDefaults sets default values for the configuration
func applyDefaults(config *Config) {
	if config.Server.HTTPPort == 0 {
		config.Server.HTTPPort = 8080
	}
	if config.Server.GRPCPort == 0 {
		config.Server.GRPCPort = 8081
	}
	if config.AWS.Region == "" {
		config.AWS.Region = "us-west-2"
	}
	if config.AWS.DocumentDB.DatabaseName == "" {
		config.AWS.DocumentDB.DatabaseName = "open-saves"
	}
	// Do not set a default for DocumentDB connection string, as it requires cluster endpoint
	// The connection string must be provided in the configuration
	// Do not set a default for S3 bucket name, as it requires the account ID
	// The bucket name must be provided in the configuration
	if config.AWS.ElastiCache.TTL == 0 {
		config.AWS.ElastiCache.TTL = 3600
	}
}
