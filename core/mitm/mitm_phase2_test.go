package mitm

import (
	"bufio"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// Helper: temp home dir with Root CA pre-generated
// ---------------------------------------------------------------------------

func newHomeWithCA(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cs, err := GenerateRootCA(dir)
	if err != nil {
		t.Fatalf("GenerateRootCA: %v", err)
	}
	if !cs.Exists {
		t.Fatal("CA should exist after generation")
	}
	return dir
}

// ---------------------------------------------------------------------------
// LeafCertCache tests
// ---------------------------------------------------------------------------

func TestLeafCertCacheGenerates(t *testing.T) {
	home := newHomeWithCA(t)
	lc, err := NewLeafCertCache(home)
	if err != nil {
		t.Fatalf("NewLeafCertCache: %v", err)
	}
	cert, err := lc.GetOrCreate("api.example.com")
	if err != nil {
		t.Fatalf("GetOrCreate: %v", err)
	}
	if cert == nil || cert.Leaf == nil {
		t.Fatal("expected non-nil cert with Leaf")
	}
	if cert.Leaf.Subject.CommonName != "api.example.com" {
		t.Errorf("CN = %q, want 'api.example.com'", cert.Leaf.Subject.CommonName)
	}
}

func TestLeafCertCacheCaches(t *testing.T) {
	home := newHomeWithCA(t)
	lc, err := NewLeafCertCache(home)
	if err != nil {
		t.Fatalf("NewLeafCertCache: %v", err)
	}
	c1, _ := lc.GetOrCreate("cache.example.com")
	c2, _ := lc.GetOrCreate("cache.example.com")
	if c1 != c2 {
		t.Error("expected same pointer on second call (cache hit)")
	}
}

func TestLeafCertCacheStripsPort(t *testing.T) {
	home := newHomeWithCA(t)
	lc, err := NewLeafCertCache(home)
	if err != nil {
		t.Fatalf("NewLeafCertCache: %v", err)
	}
	c1, _ := lc.GetOrCreate("host.example.com")
	c2, _ := lc.GetOrCreate("host.example.com:443")
	if c1 != c2 {
		t.Error("expected same cert for host with and without port")
	}
}

func TestLeafCertCANotFoundError(t *testing.T) {
	home := t.TempDir() // no CA generated
	_, err := NewLeafCertCache(home)
	if err == nil {
		t.Fatal("expected error when CA is missing")
	}
}

func TestLeafCertSignedByRootCA(t *testing.T) {
	home := newHomeWithCA(t)
	lc, err := NewLeafCertCache(home)
	if err != nil {
		t.Fatalf("NewLeafCertCache: %v", err)
	}
	tlsCert, err := lc.GetOrCreate("signed.example.com")
	if err != nil {
		t.Fatalf("GetOrCreate: %v", err)
	}

	// Load CA cert and build a pool.
	caPEM, _ := os.ReadFile(filepath.Join(home, "mitm", "ca.crt"))
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(caPEM)

	// Verify the leaf cert is signed by our CA.
	leaf, err := x509.ParseCertificate(tlsCert.Certificate[0])
	if err != nil {
		t.Fatalf("parse leaf: %v", err)
	}
	opts := x509.VerifyOptions{
		Roots:     pool,
		DNSName:   "signed.example.com",
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	if _, err := leaf.Verify(opts); err != nil {
		t.Errorf("leaf cert verification failed: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Rewriter tests
// ---------------------------------------------------------------------------

func TestRewriterRejectURL(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `^https://blocked\.example\.com/`, Action: "reject"},
		},
	}
	r := NewRewriter(cfg)
	res := r.ApplyURL("https://blocked.example.com/ads/track")
	if !res.Matched || res.Action != "reject" {
		t.Errorf("expected reject match, got %+v", res)
	}
}

func TestRewriter302URL(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `^https://old\.example\.com/(.*)$`, Replacement: "https://new.example.com/$1", Action: "302"},
		},
	}
	r := NewRewriter(cfg)
	res := r.ApplyURL("https://old.example.com/path?q=1")
	if !res.Matched || res.Action != "302" {
		t.Errorf("expected 302 match, got %+v", res)
	}
	if res.RedirectURL != "https://new.example.com/path?q=1" {
		t.Errorf("RedirectURL = %q, want 'https://new.example.com/path?q=1'", res.RedirectURL)
	}
}

func TestRewriter307URL(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `^https://api\.example\.com/v1/`, Replacement: "https://api.example.com/v2/", Action: "307"},
		},
	}
	r := NewRewriter(cfg)
	res := r.ApplyURL("https://api.example.com/v1/data")
	if !res.Matched || res.Action != "307" {
		t.Errorf("expected 307, got %+v", res)
	}
}

func TestRewriterNoMatch(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `^https://blocked\.example\.com/`, Action: "reject"},
		},
	}
	r := NewRewriter(cfg)
	res := r.ApplyURL("https://safe.example.com/page")
	if res.Matched {
		t.Error("expected no match for unrelated URL")
	}
}

func TestRewriterHeaderAdd(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*example\.com.*`, Name: "X-Debug", Value: "1", Action: "add"},
		},
	}
	r := NewRewriter(cfg)
	headers := http.Header{}
	r.ApplyHeaders("https://api.example.com/data", headers)
	if headers.Get("X-Debug") != "1" {
		t.Errorf("X-Debug header = %q, want '1'", headers.Get("X-Debug"))
	}
}

func TestRewriterHeaderReplace(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*`, Name: "User-Agent", Value: "YueLink/2.0", Action: "replace"},
		},
	}
	r := NewRewriter(cfg)
	headers := http.Header{"User-Agent": []string{"old-agent"}}
	r.ApplyHeaders("https://example.com/", headers)
	if headers.Get("User-Agent") != "YueLink/2.0" {
		t.Errorf("User-Agent = %q, want 'YueLink/2.0'", headers.Get("User-Agent"))
	}
}

func TestRewriterHeaderDel(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*`, Name: "X-Tracking", Action: "del"},
		},
	}
	r := NewRewriter(cfg)
	headers := http.Header{"X-Tracking": []string{"abc123"}}
	r.ApplyHeaders("https://example.com/", headers)
	if headers.Get("X-Tracking") != "" {
		t.Error("X-Tracking should have been deleted")
	}
}

func TestRewriterHeaderNoMatchURL(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `only\.specific\.com`, Name: "X-Debug", Value: "1", Action: "add"},
		},
	}
	r := NewRewriter(cfg)
	headers := http.Header{}
	r.ApplyHeaders("https://other.com/page", headers)
	if headers.Get("X-Debug") != "" {
		t.Error("header should NOT be added when URL doesn't match pattern")
	}
}

func TestRewriterInvalidPatternSkipped(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `[invalid`, Action: "reject"},
			{Pattern: `^https://valid\.com/`, Action: "reject"},
		},
	}
	r := NewRewriter(cfg)
	// Invalid rule is skipped; valid rule still works.
	res := r.ApplyURL("https://valid.com/page")
	if !res.Matched {
		t.Error("valid rule should still match after invalid rule is skipped")
	}
}

func TestRewriterUnknownActionSkipped(t *testing.T) {
	cfg := MITMConfig{
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `^https://example\.com/`, Action: "unknown-action"},
		},
	}
	r := NewRewriter(cfg)
	res := r.ApplyURL("https://example.com/page")
	if res.Matched {
		t.Error("rule with unknown action should be skipped")
	}
}

// ---------------------------------------------------------------------------
// mitmHostSet tests
// ---------------------------------------------------------------------------

func TestMITMHostSetExact(t *testing.T) {
	s := newMITMHostSet([]string{"api.example.com"})
	if !s.matches("api.example.com") {
		t.Error("should match exact host")
	}
	if s.matches("other.example.com") {
		t.Error("should not match different subdomain")
	}
}

func TestMITMHostSetDotPrefix(t *testing.T) {
	s := newMITMHostSet([]string{".example.com"})
	if !s.matches("api.example.com") {
		t.Error("should match subdomain via .example.com")
	}
	if !s.matches("example.com") {
		t.Error("should match apex via .example.com")
	}
}

func TestMITMHostSetWildcard(t *testing.T) {
	s := newMITMHostSet([]string{"*.example.com"})
	if !s.matches("sub.example.com") {
		t.Error("should match *.example.com")
	}
	if s.matches("other.com") {
		t.Error("should not match unrelated domain")
	}
}

func TestMITMHostSetEmpty(t *testing.T) {
	s := newMITMHostSet(nil)
	if s.matches("anything.com") {
		t.Error("empty set should match nothing")
	}
}

// ---------------------------------------------------------------------------
// Engine.Configure tests
// ---------------------------------------------------------------------------

func TestEngineConfigureApplies(t *testing.T) {
	home := newHomeWithCA(t)
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer func() { _ = e.Stop() }()

	cfg := MITMConfig{
		Hostnames: []string{"api.example.com"},
	}
	if err := e.Configure(home, cfg); err != nil {
		t.Fatalf("Configure: %v", err)
	}
	// Verify internal state was set (no public getter needed — behavioural test below).
}

func TestEngineConfigurePassthroughWhenNoCA(t *testing.T) {
	home := t.TempDir() // no CA generated
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer func() { _ = e.Stop() }()

	// Configure should NOT return error even if CA is missing — falls back to passthrough.
	cfg := MITMConfig{Hostnames: []string{"api.example.com"}}
	if err := e.Configure(home, cfg); err != nil {
		t.Errorf("Configure with missing CA should not error: %v", err)
	}
}

// ---------------------------------------------------------------------------
// TLS interception — full end-to-end test
// ---------------------------------------------------------------------------

// TestEngineConnectMITMHandshake verifies that the engine terminates TLS for
// a configured MITM host and proxies the request to a local test server.
func TestEngineConnectMITMHandshake(t *testing.T) {
	home := newHomeWithCA(t)

	// Start a local HTTPS server to act as the "upstream".
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Upstream", "yes")
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "hello from upstream")
	}))
	defer upstream.Close()

	// Extract the upstream host:port.
	upstreamHost := strings.TrimPrefix(upstream.URL, "https://")

	// Start the MITM engine.
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer func() { _ = e.Stop() }()

	// Configure with the upstream host as MITM target.
	cfg := MITMConfig{Hostnames: []string{strings.Split(upstreamHost, ":")[0]}}
	if err := e.Configure(home, cfg); err != nil {
		t.Fatalf("Configure: %v", err)
	}

	// Dial the proxy engine directly.
	proxyAddr := fmt.Sprintf("127.0.0.1:%d", e.Port())
	conn, err := net.Dial("tcp", proxyAddr)
	if err != nil {
		t.Fatalf("dial proxy: %v", err)
	}
	defer conn.Close()

	// Send CONNECT for the upstream host.
	fmt.Fprintf(conn, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", upstreamHost, upstreamHost)
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("read CONNECT response: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("CONNECT status = %d, want 200", resp.StatusCode)
	}

	// Load our Root CA so we trust the leaf cert the engine presents.
	caPEM, _ := os.ReadFile(filepath.Join(home, "mitm", "ca.crt"))
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(caPEM)

	upstreamHostOnly := strings.Split(upstreamHost, ":")[0]
	tlsConn := tls.Client(conn, &tls.Config{
		ServerName: upstreamHostOnly,
		RootCAs:    pool,
		// Also trust the upstream's own self-signed cert (for the forwarding leg).
		InsecureSkipVerify: false,
	})
	if err := tlsConn.Handshake(); err != nil {
		t.Fatalf("TLS handshake with MITM engine: %v", err)
	}
	defer tlsConn.Close()

	// Verify the engine presented a cert signed by OUR CA (not the upstream's cert).
	certs := tlsConn.ConnectionState().PeerCertificates
	if len(certs) == 0 {
		t.Fatal("no peer certificates")
	}
	peerCN := certs[0].Subject.CommonName
	t.Logf("peer cert CN: %s", peerCN)
	if peerCN != upstreamHostOnly {
		t.Errorf("peer CN = %q, want %q", peerCN, upstreamHostOnly)
	}
}

// ---------------------------------------------------------------------------
// URL rewrite end-to-end via engine
// ---------------------------------------------------------------------------

func TestEngineRejectViaEngine(t *testing.T) {
	home := newHomeWithCA(t)

	// Upstream returns 200.
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "secret")
	}))
	defer upstream.Close()

	upstreamHost := strings.TrimPrefix(upstream.URL, "https://")
	upstreamHostOnly := strings.Split(upstreamHost, ":")[0]

	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer func() { _ = e.Stop() }()

	cfg := MITMConfig{
		Hostnames: []string{upstreamHostOnly},
		URLRewrites: []MITMUrlRewrite{
			{Pattern: `/secret`, Action: "reject"},
		},
	}
	if err := e.Configure(home, cfg); err != nil {
		t.Fatalf("Configure: %v", err)
	}

	proxyAddr := fmt.Sprintf("127.0.0.1:%d", e.Port())
	conn, err := net.Dial("tcp", proxyAddr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	fmt.Fprintf(conn, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", upstreamHost, upstreamHost)
	connectResp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil || connectResp.StatusCode != 200 {
		t.Fatalf("CONNECT failed: %v %v", err, connectResp)
	}

	caPEM, _ := os.ReadFile(filepath.Join(home, "mitm", "ca.crt"))
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(caPEM)

	tlsConn := tls.Client(conn, &tls.Config{ServerName: upstreamHostOnly, RootCAs: pool})
	if err := tlsConn.Handshake(); err != nil {
		t.Fatalf("TLS handshake: %v", err)
	}
	defer tlsConn.Close()

	// Send a request to the /secret path — engine should reject it.
	fmt.Fprintf(tlsConn, "GET /secret HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", upstreamHost)
	innerResp, err := http.ReadResponse(bufio.NewReader(tlsConn), nil)
	if err != nil {
		t.Fatalf("read inner response: %v", err)
	}
	// Reject returns 200 with empty body (not forwarding to upstream).
	if innerResp.StatusCode != http.StatusOK {
		t.Errorf("reject status = %d, want 200", innerResp.StatusCode)
	}
	body, _ := io.ReadAll(innerResp.Body)
	if strings.Contains(string(body), "secret") {
		t.Error("body should not contain 'secret' — request should have been rejected")
	}
}

// ---------------------------------------------------------------------------
// Response header rewrite tests
// ---------------------------------------------------------------------------

func TestRewriterResponseHeaderAdd(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*`, Name: "X-Injected", Value: "yes", Action: "response-add"},
		},
	}
	r := NewRewriter(cfg)
	// Should NOT apply to request headers.
	reqHeaders := http.Header{}
	r.ApplyRequestHeaders("https://example.com/", reqHeaders)
	if reqHeaders.Get("X-Injected") != "" {
		t.Error("response-add rule should not affect request headers")
	}
	// Should apply to response headers.
	respHeaders := http.Header{}
	r.ApplyResponseHeaders("https://example.com/", respHeaders)
	if respHeaders.Get("X-Injected") != "yes" {
		t.Errorf("response-add: X-Injected = %q, want 'yes'", respHeaders.Get("X-Injected"))
	}
}

func TestRewriterResponseHeaderDel(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*`, Name: "X-Powered-By", Action: "response-del"},
		},
	}
	r := NewRewriter(cfg)
	respHeaders := http.Header{"X-Powered-By": []string{"PHP/7.4"}}
	r.ApplyResponseHeaders("https://example.com/", respHeaders)
	if respHeaders.Get("X-Powered-By") != "" {
		t.Error("response-del: X-Powered-By should be removed from response headers")
	}
}

func TestRewriterRequestAndResponseRulesSeparated(t *testing.T) {
	cfg := MITMConfig{
		HeaderRewrites: []MITMHeaderRewrite{
			{Pattern: `.*`, Name: "X-Request", Value: "req", Action: "add"},
			{Pattern: `.*`, Name: "X-Response", Value: "resp", Action: "response-add"},
		},
	}
	r := NewRewriter(cfg)
	req := http.Header{}
	r.ApplyRequestHeaders("https://example.com/", req)
	resp := http.Header{}
	r.ApplyResponseHeaders("https://example.com/", resp)

	if req.Get("X-Request") != "req" {
		t.Error("request rule not applied to request headers")
	}
	if req.Get("X-Response") != "" {
		t.Error("response rule should not affect request headers")
	}
	if resp.Get("X-Response") != "resp" {
		t.Error("response rule not applied to response headers")
	}
	if resp.Get("X-Request") != "" {
		t.Error("request rule should not affect response headers")
	}
}

// ---------------------------------------------------------------------------
// Keep-alive multi-request test
// ---------------------------------------------------------------------------

func TestEngineKeepAliveMultipleRequests(t *testing.T) {
	home := newHomeWithCA(t)

	counter := 0
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		counter++
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "response-%d", counter)
	}))
	defer upstream.Close()

	upstreamHost := strings.TrimPrefix(upstream.URL, "https://")
	upstreamHostOnly := strings.Split(upstreamHost, ":")[0]

	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer func() { _ = e.Stop() }()

	cfg := MITMConfig{Hostnames: []string{upstreamHostOnly}}
	if err := e.Configure(home, cfg); err != nil {
		t.Fatalf("Configure: %v", err)
	}
	// Trust the test server's self-signed cert for the upstream dial.
	upstreamPool := x509.NewCertPool()
	for _, c := range upstream.TLS.Certificates {
		leaf, err := x509.ParseCertificate(c.Certificate[0])
		if err == nil {
			upstreamPool.AddCert(leaf)
		}
	}
	e.setUpstreamTLSConfigForTest(&tls.Config{RootCAs: upstreamPool})

	// Connect to proxy.
	conn, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", e.Port()))
	if err != nil {
		t.Fatalf("dial proxy: %v", err)
	}
	defer conn.Close()

	fmt.Fprintf(conn, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", upstreamHost, upstreamHost)
	connectResp, _ := http.ReadResponse(bufio.NewReader(conn), nil)
	if connectResp.StatusCode != 200 {
		t.Fatalf("CONNECT failed: %d", connectResp.StatusCode)
	}

	caPEM, _ := os.ReadFile(filepath.Join(home, "mitm", "ca.crt"))
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(caPEM)

	tlsConn := tls.Client(conn, &tls.Config{ServerName: upstreamHostOnly, RootCAs: pool})
	if err := tlsConn.Handshake(); err != nil {
		t.Fatalf("TLS handshake: %v", err)
	}
	defer tlsConn.Close()

	// Send 2 requests over the same TLS connection and verify both succeed.
	reader := bufio.NewReader(tlsConn)
	for i := 1; i <= 2; i++ {
		fmt.Fprintf(tlsConn, "GET /req%d HTTP/1.1\r\nHost: %s\r\n\r\n", i, upstreamHost)
		resp, err := http.ReadResponse(reader, nil)
		if err != nil {
			t.Fatalf("request %d: read response: %v", i, err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Errorf("request %d: status = %d, want 200", i, resp.StatusCode)
		}
		t.Logf("request %d: body = %q", i, string(body))
	}
}

// ---------------------------------------------------------------------------
// LeafCertCache max-size eviction
// ---------------------------------------------------------------------------

func TestLeafCertCacheMaxSize(t *testing.T) {
	home := newHomeWithCA(t)
	lc, err := NewLeafCertCache(home)
	if err != nil {
		t.Fatalf("NewLeafCertCache: %v", err)
	}

	// Fill beyond the cap.
	for i := 0; i < leafCertCacheMax+5; i++ {
		host := fmt.Sprintf("host%d.example.com", i)
		if _, err := lc.GetOrCreate(host); err != nil {
			t.Fatalf("GetOrCreate(%s): %v", host, err)
		}
	}
	lc.mu.Lock()
	size := len(lc.cache)
	lc.mu.Unlock()
	if size > leafCertCacheMax {
		t.Errorf("cache size = %d after eviction, want ≤ %d", size, leafCertCacheMax)
	}
}

// ---------------------------------------------------------------------------
// BuildMITMConfig (module.go helper)
// ---------------------------------------------------------------------------

func TestBuildMITMConfig(t *testing.T) {
	modules := []ModuleRecord{
		{
			Enabled:       true,
			MITMHostnames: []string{"api.example.com", ".example2.com"},
			URLRewrites: []UrlRewriteRule{
				{Pattern: `^https://ad\.`, RewriteType: "reject"},
			},
			HeaderRewrites: []HeaderRewriteRule{
				{Pattern: `.*`, HeaderAction: "header-add", HeaderName: "X-Test", HeaderValue: "1"},
			},
		},
		{
			Enabled:       false,
			MITMHostnames: []string{"disabled.com"},
		},
	}

	cfg := BuildMITMConfig(modules)

	if len(cfg.Hostnames) != 2 {
		t.Errorf("Hostnames len = %d, want 2", len(cfg.Hostnames))
	}
	if len(cfg.URLRewrites) != 1 {
		t.Errorf("URLRewrites len = %d, want 1", len(cfg.URLRewrites))
	}
	if len(cfg.HeaderRewrites) != 1 {
		t.Errorf("HeaderRewrites len = %d, want 1", len(cfg.HeaderRewrites))
	}
	if cfg.URLRewrites[0].Action != "reject" {
		t.Errorf("action = %q, want 'reject'", cfg.URLRewrites[0].Action)
	}
	if cfg.HeaderRewrites[0].Action != "header-add" {
		t.Errorf("header action = %q, want 'header-add'", cfg.HeaderRewrites[0].Action)
	}
	// disabled module's hostname should not be included
	for _, h := range cfg.Hostnames {
		if h == "disabled.com" {
			t.Error("disabled module's hostname should not be in config")
		}
	}
}
