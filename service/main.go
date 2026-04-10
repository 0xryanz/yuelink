package main

import (
	"context"
	"flag"
	"log"
	"os/signal"
)

func main() {
	var configPath string
	flag.StringVar(&configPath, "config", "", "Path to service config JSON")
	flag.Parse()

	if configPath == "" {
		log.Fatal("missing -config")
	}

	if isService, err := isWindowsService(); err == nil && isService {
		if err := runWindowsService(configPath); err != nil {
			log.Fatal(err)
		}
		return
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		log.Fatal(err)
	}
	if err := configureLogging(cfg.HelperLogPath); err != nil {
		log.Fatal(err)
	}

	runtime, err := NewServiceRuntime(cfg)
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), serviceSignals()...)
	defer cancel()
	if err := runtime.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
