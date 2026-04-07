package mitm

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	defaultMITMPort = 9091
	shutdownTimeout = 5 * time.Second
	healthCheckPath = "/ping"
)

// mitmHostSet holds normalised hostname rules for fast membership testing.
type mitmHostSet struct {
	exact  map[string]struct{} // "api.example.com"
	suffix map[string]struct{} // "example.com" (from ".example.com" or "*.example.com")
}

func newMITMHostSet(hostnames []string) *mitmHostSet {
	s := &mitmHostSet{
		exact:  make(map[string]struct{}),
		suffix: make(map[string]struct{}),
	}
	for _, h := range hostnames {
		h = strings.TrimSpace(h)
		if h == "" {
			continue
		}
		if strings.HasPrefix(h, "*.") {
			s.suffix[h[2:]] = struct{}{}
		} else if strings.HasPrefix(h, ".") {
			s.suffix[h[1:]] = struct{}{}
		} else {
			s.exact[h] = struct{}{}
		}
	}
	return s
}

// matches returns true if host (no port) is covered by this set.
func (s *mitmHostSet) matches(host string) bool {
	if _, ok := s.exact[host]; ok {
		return true
	}
	for suffix := range s.suffix {
		if host == suffix || strings.HasSuffix(host, "."+suffix) {
			return true
		}
	}
	return false
}

// Engine is the MITM proxy engine.
type Engine struct {
	port      int
	server    *http.Server
	listener  net.Listener
	running   bool
	startedAt *time.Time
	lastError string
	mu        sync.Mutex

	// Phase 2 interception fields (set via Configure; nil = passthrough mode).
	leafCache         *LeafCertCache
	mitmHosts         *mitmHostSet
	rewriter          *Rewriter
	scripts           []compiledScript // Phase 2C: response scripts
	upstreamTLSConfig *tls.Config      // nil = system roots (production); non-nil = testing override
}

// NewEngine creates a new engine with the given preferred port.
// Pass 0 to use the default port (9091).
func NewEngine(port int) *Engine {
	if port <= 0 {
		port = defaultMITMPort
	}
	return &Engine{port: port}
}

// Start starts the engine. Tries the preferred port first; falls back to an
// OS-assigned port if the preferred port is busy. Updates e.port with the
// actual bound port.
func (e *Engine) Start() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.running {
		return fmt.Errorf("[MITM] engine is already running on port %d", e.port)
	}

	// Try preferred port, then fall back to OS-assigned.
	preferredAddr := fmt.Sprintf("127.0.0.1:%d", e.port)
	ln, err := net.Listen("tcp", preferredAddr)
	if err != nil {
		logEngine("preferred port %d busy, falling back to OS-assigned port", e.port)
		ln, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return fmt.Errorf("[MITM] cannot bind: %w", err)
		}
	}

	// Record the actual port from the listener.
	e.port = ln.Addr().(*net.TCPAddr).Port
	e.listener = ln

	// Use a plain HandlerFunc instead of ServeMux so that CONNECT requests
	// (whose request-URI is "host:port", not a path) reach handleRequest.
	// ServeMux's "/" fallback does not match CONNECT URIs.
	e.server = &http.Server{
		Handler: http.HandlerFunc(e.handleRequest),
	}

	logEngine("starting on 127.0.0.1:%d", e.port)

	// Capture srv locally so the goroutine always holds a valid reference
	// even if Stop() sets e.server = nil before this goroutine is scheduled.
	srv := e.server
	go func() {
		if serveErr := srv.Serve(ln); serveErr != nil && serveErr != http.ErrServerClosed {
			e.mu.Lock()
			e.lastError = serveErr.Error()
			e.running = false
			e.startedAt = nil
			e.mu.Unlock()
			logEngine("serve error: %v", serveErr)
		}
	}()

	now := time.Now().UTC()
	e.startedAt = &now
	e.running = true
	e.lastError = ""
	logEngine("started on 127.0.0.1:%d", e.port)
	return nil
}

// Stop gracefully stops the engine with a 5-second timeout.
func (e *Engine) Stop() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if !e.running {
		return nil // idempotent
	}

	logEngine("stopping …")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := e.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("[MITM] shutdown error: %w", err)
	}

	e.running = false
	e.startedAt = nil
	e.server = nil
	e.listener = nil
	logEngine("stopped")
	return nil
}

// IsRunning returns the current running state.
func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

// Port returns the actual bound port (valid after Start succeeds).
func (e *Engine) Port() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.port
}

// HealthCheck pings the engine's own /ping endpoint to verify it is actually
// responding to connections. Returns nil if healthy.
func (e *Engine) HealthCheck() error {
	e.mu.Lock()
	port := e.port
	running := e.running
	e.mu.Unlock()

	if !running {
		return fmt.Errorf("[MITM] engine not running")
	}

	url := fmt.Sprintf("http://127.0.0.1:%d%s", port, healthCheckPath)
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return fmt.Errorf("[MITM] health check failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("[MITM] health check returned HTTP %d", resp.StatusCode)
	}
	return nil
}

// Status returns a MitmEngineStatus snapshot.
func (e *Engine) Status() MitmEngineStatus {
	e.mu.Lock()
	defer e.mu.Unlock()

	addr := ""
	if e.running {
		addr = fmt.Sprintf("127.0.0.1:%d", e.port)
	}

	healthy := false
	if e.running {
		// Non-blocking health probe: dial the port rather than doing an HTTP GET
		// (avoids a recursive lock). A successful dial is a good-enough liveness
		// check inside a lock-free fast path; callers that need the full HTTP
		// probe can call HealthCheck() directly.
		conn, dialErr := net.DialTimeout("tcp", addr, 200*time.Millisecond)
		if dialErr == nil {
			conn.Close()
			healthy = true
		}
	}

	return MitmEngineStatus{
		Running:   e.running,
		Port:      e.port,
		Address:   addr,
		StartedAt: e.startedAt,
		Healthy:   healthy,
		LastError: e.lastError,
	}
}

// handleRequest dispatches incoming proxy requests.
// GET /ping   → health check.
// CONNECT     → passthrough tunnel (Phase 1, no MITM interception yet).
// Anything else → 501.
func (e *Engine) handleRequest(w http.ResponseWriter, r *http.Request) {
	// Health-check: direct GET /ping (not a proxy request).
	if r.Method == http.MethodGet && r.URL.Path == healthCheckPath {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok","engine":"YueLink Module Runtime"}`))
		return
	}
	if r.Method == http.MethodConnect {
		e.handleConnect(w, r)
		return
	}
	logEngine("unsupported method %s %s (Phase 1 passthrough only)", r.Method, r.RequestURI)
	http.Error(w, "Method Not Allowed — YueLink Module Runtime Phase 1", http.StatusNotImplemented)
}

// Configure sets the Phase 2 interception config on the engine.
// Safe to call while the engine is running; takes effect for new connections.
// homeDir must be the same directory passed to InitCore so the CA files exist.
func (e *Engine) Configure(homeDir string, cfg MITMConfig) error {
	hosts := newMITMHostSet(cfg.Hostnames)
	rewriter := NewRewriter(cfg)

	var lc *LeafCertCache
	if len(cfg.Hostnames) > 0 {
		var err error
		lc, err = NewLeafCertCache(homeDir)
		if err != nil {
			// Log but don't return error — engine still works in passthrough mode.
			logEngine("configure: leaf cert cache unavailable (%v); falling back to passthrough", err)
		}
	}

	scripts := compileScripts(cfg.Scripts)

	e.mu.Lock()
	e.leafCache = lc
	e.mitmHosts = hosts
	e.rewriter = rewriter
	e.scripts = scripts
	e.mu.Unlock()

	logEngine("configured: %d MITM hosts, %d URL rules, %d header rules, %d scripts",
		len(cfg.Hostnames), len(cfg.URLRewrites), len(cfg.HeaderRewrites), len(scripts))
	return nil
}

// handleConnect dispatches a CONNECT request: MITM interception for hosts in
// the configured set (when CA is loaded), passthrough for everything else.
func (e *Engine) handleConnect(w http.ResponseWriter, r *http.Request) {
	// Snapshot Phase-2 fields under lock; nil = passthrough.
	e.mu.Lock()
	leafCache := e.leafCache
	mitmHosts := e.mitmHosts
	rewriter := e.rewriter
	scripts := e.scripts
	upstreamTLSCfg := e.upstreamTLSConfig
	e.mu.Unlock()

	host, _, err := net.SplitHostPort(r.Host)
	if err != nil {
		host = r.Host // no port, use as-is
	}
	if leafCache != nil && mitmHosts != nil && mitmHosts.matches(host) {
		logEngine("CONNECT %s → MITM intercept", r.Host)
		e.handleConnectMITM(w, r, host, leafCache, rewriter, scripts, upstreamTLSCfg)
		return
	}

	logEngine("CONNECT %s (passthrough)", r.Host)

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		logEngine("CONNECT hijack error: %v", err)
		return
	}
	defer clientConn.Close()

	// Respond 200 Connection Established.
	if _, werr := clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); werr != nil {
		logEngine("CONNECT write 200 error: %v", werr)
		return
	}

	// Dial the upstream target.
	targetConn, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
	if err != nil {
		logEngine("CONNECT dial %s failed: %v", r.Host, err)
		return
	}
	defer targetConn.Close()

	// Bidirectional copy until either side closes.
	done := make(chan struct{}, 2)
	pipe := func(dst net.Conn, src net.Conn) {
		buf := make([]byte, 32*1024)
		for {
			n, readErr := src.Read(buf)
			if n > 0 {
				if _, writeErr := dst.Write(buf[:n]); writeErr != nil {
					break
				}
			}
			if readErr != nil {
				break
			}
		}
		done <- struct{}{}
	}
	go pipe(targetConn, clientConn)
	go pipe(clientConn, targetConn)
	<-done
}

// handleConnectMITM terminates TLS for a CONNECT-tunnelled connection, then
// processes all HTTP/1.1 requests on that connection (keep-alive loop).
// Per-request flow: URL rewrite → request header rewrite → forward →
//
//	response script → response header rewrite → write response to client.
//
// setUpstreamTLSConfigForTest overrides the TLS config used for upstream connections.
// Intended for testing only — allows trusting a local test server's self-signed cert.
// Pass nil to restore default (system root CA pool).
func (e *Engine) setUpstreamTLSConfigForTest(cfg *tls.Config) {
	e.mu.Lock()
	e.upstreamTLSConfig = cfg
	e.mu.Unlock()
}

func (e *Engine) handleConnectMITM(
	w http.ResponseWriter,
	r *http.Request,
	host string, // bare hostname (no port)
	leafCache *LeafCertCache,
	rewriter *Rewriter,
	scripts []compiledScript,
	upstreamTLSOverride *tls.Config, // nil = system roots
) {
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}
	rawConn, _, err := hj.Hijack()
	if err != nil {
		logTLS("hijack error: %v", err)
		return
	}
	defer rawConn.Close()

	// Acknowledge the CONNECT tunnel.
	if _, err := rawConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
		logTLS("200 write error: %v", err)
		return
	}

	// TLS handshake — present the leaf cert for the target host.
	tlsCert, err := leafCache.GetOrCreate(host)
	if err != nil {
		logTLS("leaf cert error for %s: %v", host, err)
		return
	}
	tlsConn := tls.Server(rawConn, &tls.Config{
		Certificates: []tls.Certificate{*tlsCert},
	})
	if err := tlsConn.Handshake(); err != nil {
		logTLS("handshake error for %s: %v", host, err)
		return
	}
	defer tlsConn.Close()
	logTLS("established for %s", host)

	// Upstream address for this CONNECT target.
	upstreamAddr := r.Host
	if _, _, splitErr := net.SplitHostPort(r.Host); splitErr != nil {
		upstreamAddr = r.Host + ":443"
	}

	// Keep a single bufio.Reader for the TLS connection so the internal
	// buffer is preserved across requests (HTTP/1.1 keep-alive).
	reader := bufio.NewReader(tlsConn)

	for {
		innerReq, err := http.ReadRequest(reader)
		if err != nil {
			// EOF or reset — client closed the connection normally.
			if err.Error() != "EOF" {
				logTLS("read request error for %s: %v", host, err)
			}
			return
		}

		fullURL := "https://" + r.Host + innerReq.RequestURI
		logEngine("[MITM] %s %s", innerReq.Method, fullURL)

		// ── URL rewrite ──────────────────────────────────────────────
		if rewriter != nil {
			if res := rewriter.ApplyURL(fullURL); res.Matched {
				switch res.Action {
				case "reject":
					logRewrite("reject: %s", fullURL)
					_, _ = fmt.Fprintf(tlsConn,
						"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
					return
				case "302":
					logRewrite("302: %s → %s", fullURL, res.RedirectURL)
					_, _ = fmt.Fprintf(tlsConn,
						"HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
						res.RedirectURL)
					return
				case "307":
					logRewrite("307: %s → %s", fullURL, res.RedirectURL)
					_, _ = fmt.Fprintf(tlsConn,
						"HTTP/1.1 307 Temporary Redirect\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
						res.RedirectURL)
					return
				}
			}
		}

		// ── Request header rewrites ──────────────────────────────────
		if rewriter != nil {
			rewriter.ApplyRequestHeaders(fullURL, innerReq.Header)
		}

		// ── Forward to real upstream ─────────────────────────────────
		upstreamTLS := &tls.Config{ServerName: host}
		if upstreamTLSOverride != nil {
			upstreamTLS = upstreamTLSOverride.Clone()
			upstreamTLS.ServerName = host
		}
		upstreamConn, dialErr := tls.Dial("tcp", upstreamAddr, upstreamTLS)
		if dialErr != nil {
			logTLS("upstream dial error for %s: %v", upstreamAddr, dialErr)
			_, _ = fmt.Fprintf(tlsConn,
				"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
			return
		}

		// Ensure Host header is set and clear RequestURI so Write uses URL.
		if innerReq.Host == "" {
			innerReq.Host = r.Host
		}
		savedURI := innerReq.RequestURI
		innerReq.RequestURI = ""
		writeErr := innerReq.Write(upstreamConn)
		innerReq.RequestURI = savedURI
		if writeErr != nil {
			upstreamConn.Close()
			logEngine("[MITM] upstream write error for %s: %v", host, writeErr)
			return
		}

		upstreamResp, respErr := http.ReadResponse(bufio.NewReader(upstreamConn), innerReq)
		if respErr != nil {
			upstreamConn.Close()
			logEngine("[MITM] upstream read response error for %s: %v", host, respErr)
			return
		}

		// ── Response scripts ─────────────────────────────────────────
		// Runs before response header rewrites so scripts can set headers
		// that header-rewrite rules may then further modify.
		upstreamResp = RunResponseScriptsOnHTTP(scripts, innerReq, upstreamResp, fullURL)

		// ── Response header rewrites ─────────────────────────────────
		if rewriter != nil {
			rewriter.ApplyResponseHeaders(fullURL, upstreamResp.Header)
		}

		// Propagate keep-alive decision: honour both sides.
		clientWantsClose := strings.EqualFold(innerReq.Header.Get("Connection"), "close") ||
			!innerReq.ProtoAtLeast(1, 1)
		serverWantsClose := strings.EqualFold(upstreamResp.Header.Get("Connection"), "close")
		shouldClose := clientWantsClose || serverWantsClose
		if shouldClose {
			upstreamResp.Header.Set("Connection", "close")
		}

		sendErr := upstreamResp.Write(tlsConn)
		upstreamResp.Body.Close()
		upstreamConn.Close()

		if sendErr != nil {
			logEngine("[MITM] response write error for %s: %v", host, sendErr)
			return
		}
		if shouldClose {
			return
		}
	}
}

// ---------------------------------------------------------------------------
// Global singleton for FFI access
// ---------------------------------------------------------------------------

var (
	globalEngineMu sync.Mutex
	globalEngine   *Engine
)

// StartMITMEngine starts the global MITM engine singleton on the given port.
// Pass 0 to use the default port.
func StartMITMEngine(port int) error {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine != nil && globalEngine.IsRunning() {
		return fmt.Errorf("[MITM] global engine already running")
	}
	globalEngine = NewEngine(port)
	return globalEngine.Start()
}

// StopMITMEngine stops the global MITM engine singleton.
func StopMITMEngine() error {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		return nil
	}
	err := globalEngine.Stop()
	globalEngine = nil
	return err
}

// GetMITMEngineStatus returns the status of the global MITM engine.
func GetMITMEngineStatus() MitmEngineStatus {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		// Port: 0 when not running — callers should check Running first.
		// Returning defaultMITMPort here was misleading: 9091 has never
		// been bound, so reporting it as the port is semantically wrong.
		return MitmEngineStatus{Running: false, Port: 0}
	}
	return globalEngine.Status()
}

// ConfigureMITMEngine sets the Phase 2 interception config on the global engine.
// Must be called after StartMITMEngine. Safe to call while the engine is running.
func ConfigureMITMEngine(homeDir string, cfg MITMConfig) error {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		return fmt.Errorf("[MITM] global engine not started")
	}
	return globalEngine.Configure(homeDir, cfg)
}

// MITMEngineStatusJSON returns the current engine status serialised as JSON.
// Exported for testing convenience.
func MITMEngineStatusJSON() ([]byte, error) {
	return json.Marshal(GetMITMEngineStatus())
}
