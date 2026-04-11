//go:build darwin || linux

package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
)

func init() {
	openTransport = startUnixTransport
}

// startUnixTransport listens on a Unix domain socket at cfg.SocketPath and
// hands accepted connections to runtime.Run. Every accepted connection is
// peer-credential-checked: only callers whose UID matches cfg.OwnerUID
// proceed; everyone else is closed before any HTTP framing happens.
//
// Why this is the macOS/Linux fix for the P0 finding: the previous design
// listened on TCP loopback with a bearer token stored in the user's
// settings.json (plaintext). Any local process running as the user could
// read the token and impersonate YueLink. With Unix-socket + getpeereid,
// the OS itself authenticates the caller — no token to steal, no listening
// port to scan.
func startUnixTransport(runtime *ServiceRuntime) (net.Listener, http.Handler, error) {
	cfg := runtime.cfg
	if cfg.SocketPath == "" {
		return nil, nil, fmt.Errorf("missing socket_path in config")
	}

	// Make sure the parent directory exists and is writable.
	if err := os.MkdirAll(filepath.Dir(cfg.SocketPath), 0o755); err != nil {
		return nil, nil, fmt.Errorf("mkdir socket parent: %w", err)
	}
	// Remove stale socket from a previous run.
	_ = os.Remove(cfg.SocketPath)

	raw, err := net.Listen("unix", cfg.SocketPath)
	if err != nil {
		return nil, nil, fmt.Errorf("listen unix %s: %w", cfg.SocketPath, err)
	}

	// 0666: any user can connect. The actual auth is getpeereid below.
	// We can't restrict the file mode to a single user without knowing
	// their gid in advance and chowning, but it doesn't matter — peer
	// cred check rejects everyone except OwnerUID anyway.
	if err := os.Chmod(cfg.SocketPath, 0o666); err != nil {
		_ = raw.Close()
		return nil, nil, fmt.Errorf("chmod socket: %w", err)
	}

	wrapped := &peerCredListener{
		Listener: raw,
		ownerUID: uint32(cfg.OwnerUID),
	}
	return wrapped, runtime.newHandler(), nil
}

// peerCredListener wraps a Unix-socket listener and rejects connections
// whose peer UID does not match ownerUID. Rejected connections are closed
// immediately and never reach the HTTP server.
type peerCredListener struct {
	net.Listener
	ownerUID uint32
	rejected uint64
}

func (l *peerCredListener) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		uid, ok := getPeerUID(conn)
		if !ok {
			_ = conn.Close()
			atomic.AddUint64(&l.rejected, 1)
			log.Printf("[auth] rejected connection: cannot read peer credential")
			continue
		}
		if uid != l.ownerUID {
			_ = conn.Close()
			atomic.AddUint64(&l.rejected, 1)
			log.Printf("[auth] rejected connection: peer uid=%d, expected %d", uid, l.ownerUID)
			continue
		}
		return conn, nil
	}
}

// getPeerUID is implemented per-OS in peer_cred_linux.go / peer_cred_darwin.go.
// Linux uses SO_PEERCRED + Ucred; macOS uses LOCAL_PEERCRED + Xucred.
