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
	// Legacy HTTP defaults — only used by the Windows transport now;
	// macOS/Linux moved to Unix sockets and ignore these.
	defaultListenHost = "127.0.0.1"
	defaultListenPort = 28653
)

type Config struct {
	// HTTP transport (Windows only) — ignored by Unix-socket transport.
	Token      string `json:"token,omitempty"`
	ListenHost string `json:"listen_host,omitempty"`
	ListenPort int    `json:"listen_port,omitempty"`

	// Unix socket transport (macOS / Linux). Absolute path.
	SocketPath string `json:"socket_path,omitempty"`

	// Owner identity captured at install time. The helper accepts requests
	// only from connections whose peer credential UID matches OwnerUID.
	// On Windows where peer cred is harder, OwnerUID is informational and
	// the bearer Token + loopback bind is the auth.
	OwnerUID int `json:"owner_uid"`

	// Path allowlist — only home_dir / config_path values inside one of
	// these prefixes are accepted. Captured at install time so the user
	// can't talk the helper into writing files anywhere.
	AllowedHomeDirs []string `json:"allowed_home_dirs"`

	// Path to the bundled mihomo binary, set at install time. Cannot be
	// overridden by clients.
	MihomoPath string `json:"mihomo_path"`

	// Helper's own log file. Owned and written by the helper, never the
	// client. Only used to redirect helper's stdout/stderr.
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

	// Backwards-compatible defaults for the HTTP transport (Windows).
	if cfg.ListenHost == "" {
		cfg.ListenHost = defaultListenHost
	}
	if cfg.ListenPort == 0 {
		cfg.ListenPort = defaultListenPort
	}

	if cfg.MihomoPath == "" {
		return nil, fmt.Errorf("missing mihomo_path")
	}
	if len(cfg.AllowedHomeDirs) == 0 {
		return nil, fmt.Errorf("missing allowed_home_dirs (set at install time)")
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
