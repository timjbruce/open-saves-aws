package main

import (
	"flag"
	"log"
	"os"

	"github.com/googleforgames/open-saves/aws-adapter/server"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "config/config.yaml", "Path to configuration file or Parameter Store path")
	paramStore := flag.Bool("param-store", false, "Use AWS Parameter Store for configuration")
	flag.Parse()

	// Determine configuration source
	configSource := *configPath
	if *paramStore {
		// Check if environment variable is set
		if envParam := os.Getenv("OPEN_SAVES_CONFIG_PARAM"); envParam != "" {
			configSource = envParam
		} else {
			// Default Parameter Store path
			configSource = "/open-saves/dev/config"
		}
	}

	// Load configuration
	config, err := server.LoadConfig(configSource)
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Create and start server
	srv, err := server.NewServer(config)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}

	log.Printf("Starting Open Saves AWS adapter")
	if err := srv.Start(); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
