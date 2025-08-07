package main

import (
	"flag"
	"fmt"
	"log"

	"github.com/googleforgames/open-saves/aws-adapter/server"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "/open-saves/dev/config", "Path to Parameter Store configuration")
	flag.Parse()

	// Use the Parameter Store path directly
	configSource := *configPath

	fmt.Printf("DEBUG MAIN: configPath=%s, configSource=%s\n", *configPath, configSource)

	// Load configuration from Parameter Store
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
