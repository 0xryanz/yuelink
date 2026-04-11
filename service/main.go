package main

import (
	"context"
	"flag"
	"log"
	"net"
	"net/http"
	"os/signal"
	"runtime"
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

	rt, err := NewServiceRuntime(cfg)
	if err != nil {
		log.Fatal(err)
	}

	listener, handler, err := openTransport(rt)
	if err != nil {
		log.Fatalf("[service] open transport: %v", err)
	}
	log.Printf("[service] platform=%s owner_uid=%d", runtime.GOOS, cfg.OwnerUID)

	ctx, cancel := signal.NotifyContext(context.Background(), serviceSignals()...)
	defer cancel()
	if err := rt.Run(ctx, listener, handler); err != nil {
		log.Fatal(err)
	}
}

// openTransport is a tiny indirection so we can pick the right transport
// (Unix socket on macOS/Linux, HTTP loopback on Windows) without sprinkling
// build tags through main(). The actual implementations live in
// transport_unix.go (build: darwin || linux) and transport_windows.go
// (build: windows). The variable below is set in those files via init().
var openTransport func(rt *ServiceRuntime) (net.Listener, http.Handler, error)
