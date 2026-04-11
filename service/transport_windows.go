//go:build windows

package main

import (
	"fmt"
	"net"
	"net/http"
)

func init() {
	openTransport = startHTTPLoopbackTransport
}

// startHTTPLoopbackTransport listens on 127.0.0.1:port (so only local
// processes can connect) and authenticates clients with a bearer token
// stored in the install-time helper config.
//
// On Windows, Dart doesn't have a clean Named Pipe API and Go-side
// peer-credential lookup via GetExtendedTcpTable + OpenProcessToken is a
// significant amount of FFI work. For v1 we keep the HTTP+token design
// here but combine it with:
//   - 127.0.0.1 bind (no remote attackers)
//   - install-time path allowlist (no path injection)
//   - file-based config_path (no raw content over the wire)
//
// All three of those are NEW in this revision; previously the helper
// happily accepted any home_dir + raw config_yaml from any token-bearing
// caller. The remaining attack — local user-mode malware steals the token
// from settings.json + impersonates the user — is acknowledged in the
// release notes as a known limitation on Windows pending Named Pipe support.
func startHTTPLoopbackTransport(runtime *ServiceRuntime) (net.Listener, http.Handler, error) {
	cfg := runtime.cfg
	if cfg.Token == "" {
		return nil, nil, fmt.Errorf("missing token in config (Windows transport requires it)")
	}
	addr := fmt.Sprintf("%s:%d", cfg.ListenHost, cfg.ListenPort)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, nil, fmt.Errorf("listen %s: %w", addr, err)
	}
	return listener, runtime.withTokenAuth(runtime.newHandler()), nil
}
