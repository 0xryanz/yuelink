package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
)

// Version is set at build time via -ldflags "-X main.Version=..."
// Falls back to "dev" for local builds.
var Version = "dev"

const (
	defaultListenHost = "127.0.0.1"
	defaultListenPort = 28653
)

type Config struct {
	Token         string `json:"token"`
	ListenHost    string `json:"listen_host"`
	ListenPort    int    `json:"listen_port"`
	MihomoPath    string `json:"mihomo_path"`
	HelperLogPath string `json:"helper_log_path,omitempty"`
}

func loadConfig(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if cfg.ListenHost == "" {
		cfg.ListenHost = defaultListenHost
	}
	if cfg.ListenPort == 0 {
		cfg.ListenPort = defaultListenPort
	}
	if cfg.Token == "" {
		return nil, fmt.Errorf("missing token")
	}
	if cfg.MihomoPath == "" {
		return nil, fmt.Errorf("missing mihomo_path")
	}

	return &cfg, nil
}

func configureLogging(path string) error {
	if path == "" {
		return nil
	}

	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return fmt.Errorf("open helper log: %w", err)
	}
	log.SetOutput(io.MultiWriter(os.Stdout, f))
	return nil
}
