package mitm

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Engine lifecycle tests
// ---------------------------------------------------------------------------

func TestEngineStartStop(t *testing.T) {
	e := NewEngine(0) // OS-assigned port

	// Initially not running
	if e.IsRunning() {
		t.Fatal("new engine should not be running")
	}

	// Start
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	if !e.IsRunning() {
		t.Fatal("engine should be running after Start()")
	}
	if e.Port() == 0 {
		t.Fatal("Port() should be non-zero after Start()")
	}
	t.Logf("engine started on port %d", e.Port())

	// Stop
	if err := e.Stop(); err != nil {
		t.Fatalf("Stop() failed: %v", err)
	}
	if e.IsRunning() {
		t.Fatal("engine should not be running after Stop()")
	}
}

func TestEngineIdempotentStart(t *testing.T) {
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()

	// Second Start() must return an error, not panic
	if err := e.Start(); err == nil {
		t.Fatal("second Start() should return error")
	}
}

func TestEngineIdempotentStop(t *testing.T) {
	e := NewEngine(0)
	// Stop when not running must be a no-op (nil error)
	if err := e.Stop(); err != nil {
		t.Fatalf("Stop() on idle engine should be nil, got: %v", err)
	}
}

func TestEnginePortConflictFallback(t *testing.T) {
	// Grab a port to force a conflict
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to grab a port: %v", err)
	}
	occupiedPort := ln.Addr().(*net.TCPAddr).Port
	// Keep ln open so the port is busy
	defer ln.Close()

	e := NewEngine(occupiedPort)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() should succeed by falling back, got: %v", err)
	}
	defer e.Stop()

	if e.Port() == occupiedPort {
		t.Errorf("expected fallback port, got same port %d", occupiedPort)
	}
	t.Logf("fallback: preferred=%d actual=%d", occupiedPort, e.Port())
}

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

func TestEngineHealthCheck(t *testing.T) {
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()

	if err := e.HealthCheck(); err != nil {
		t.Fatalf("HealthCheck() failed: %v", err)
	}
}

func TestEnginePingEndpoint(t *testing.T) {
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()

	url := fmt.Sprintf("http://127.0.0.1:%d/ping", e.Port())
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		t.Fatalf("GET /ping failed: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
	if !strings.Contains(string(body), "ok") {
		t.Fatalf("expected body to contain 'ok', got: %s", body)
	}
	t.Logf("/ping response: %s", body)
}

// ---------------------------------------------------------------------------
// Status JSON
// ---------------------------------------------------------------------------

func TestEngineStatusJSON(t *testing.T) {
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()

	status := e.Status()

	if !status.Running {
		t.Error("status.Running should be true")
	}
	if status.Port == 0 {
		t.Error("status.Port should be non-zero")
	}
	if status.Port != e.Port() {
		t.Errorf("status.Port %d != e.Port() %d", status.Port, e.Port())
	}
	if status.Address == "" {
		t.Error("status.Address should not be empty")
	}

	// Verify JSON serialisation round-trips correctly
	data, err := json.Marshal(status)
	if err != nil {
		t.Fatalf("json.Marshal failed: %v", err)
	}
	var m map[string]interface{}
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("json.Unmarshal failed: %v", err)
	}
	if m["running"] != true {
		t.Errorf("JSON running field: expected true, got %v", m["running"])
	}
	portFloat, ok := m["port"].(float64)
	if !ok || int(portFloat) != e.Port() {
		t.Errorf("JSON port field mismatch: expected %d, got %v", e.Port(), m["port"])
	}
	t.Logf("status JSON: %s", data)
}

func TestEngineStatusStoppedPort(t *testing.T) {
	// Validate that GetMITMEngineStatus (global singleton path) returns
	// Port=0 (not defaultMITMPort=9091) when engine is not running.
	// We test the global helpers directly.
	status := GetMITMEngineStatus()
	if status.Running {
		// Another test may have left it running; skip gracefully
		t.Skip("global engine is running; start a separate engine instance for this test")
	}
	if status.Port != 0 {
		t.Errorf("stopped engine status should have Port=0, got %d", status.Port)
	}
}

// ---------------------------------------------------------------------------
// CONNECT passthrough
// ---------------------------------------------------------------------------

func TestEngineConnectPassthrough(t *testing.T) {
	// Start an echo server that records the first few bytes
	echoLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("echo server listen: %v", err)
	}
	echoPort := echoLn.Addr().(*net.TCPAddr).Port
	connected := make(chan struct{}, 1)
	go func() {
		conn, _ := echoLn.Accept()
		if conn != nil {
			connected <- struct{}{}
			conn.Close()
		}
	}()
	defer echoLn.Close()

	// Start MITM engine
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()

	// Send CONNECT to the engine targeting our echo server
	proxyAddr := fmt.Sprintf("127.0.0.1:%d", e.Port())
	target := fmt.Sprintf("127.0.0.1:%d", echoPort)

	conn, err := net.DialTimeout("tcp", proxyAddr, 2*time.Second)
	if err != nil {
		t.Fatalf("dial proxy failed: %v", err)
	}
	defer conn.Close()

	connectReq := fmt.Sprintf("CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", target, target)
	if _, err := conn.Write([]byte(connectReq)); err != nil {
		t.Fatalf("write CONNECT failed: %v", err)
	}

	// Read 200 response
	buf := make([]byte, 256)
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err := conn.Read(buf)
	if err != nil {
		t.Fatalf("read 200 response failed: %v", err)
	}
	resp := string(buf[:n])
	if !strings.Contains(resp, "200") {
		t.Fatalf("expected 200 Connection Established, got: %s", resp)
	}

	// Verify the echo server received the connection
	select {
	case <-connected:
		t.Log("CONNECT passthrough verified: echo server received connection")
	case <-time.After(2 * time.Second):
		t.Fatal("echo server did not receive connection within 2s")
	}
}

// ---------------------------------------------------------------------------
// HostnameRules
// ---------------------------------------------------------------------------

func TestHostnameRulesExact(t *testing.T) {
	mods := []ModuleRecord{
		{Enabled: true, MITMHostnames: []string{"example.com"}},
	}
	rules := HostnameRules(mods)
	if len(rules) != 1 || rules[0] != "DOMAIN,example.com,_mitm_engine" {
		t.Errorf("unexpected rules: %v", rules)
	}
}

func TestHostnameRulesDotPrefix(t *testing.T) {
	mods := []ModuleRecord{
		{Enabled: true, MITMHostnames: []string{".example.com"}},
	}
	rules := HostnameRules(mods)
	if len(rules) != 1 || rules[0] != "DOMAIN-SUFFIX,example.com,_mitm_engine" {
		t.Errorf("unexpected rules: %v", rules)
	}
}

func TestHostnameRulesWildcard(t *testing.T) {
	mods := []ModuleRecord{
		{Enabled: true, MITMHostnames: []string{"*.example.com"}},
	}
	rules := HostnameRules(mods)
	if len(rules) != 1 || rules[0] != "DOMAIN-SUFFIX,example.com,_mitm_engine" {
		t.Errorf("unexpected rules: %v", rules)
	}
}

func TestHostnameRulesDeduplication(t *testing.T) {
	mods := []ModuleRecord{
		{Enabled: true, MITMHostnames: []string{".example.com", "*.example.com"}},
		{Enabled: true, MITMHostnames: []string{".example.com"}},
	}
	rules := HostnameRules(mods)
	// Both .example.com and *.example.com produce the same rule
	// so deduplication should yield only 1 rule
	if len(rules) != 1 {
		t.Errorf("expected 1 deduplicated rule, got %d: %v", len(rules), rules)
	}
}

func TestHostnameRulesDisabledModuleSkipped(t *testing.T) {
	mods := []ModuleRecord{
		{Enabled: false, MITMHostnames: []string{"secret.com"}},
		{Enabled: true, MITMHostnames: []string{"public.com"}},
	}
	rules := HostnameRules(mods)
	for _, r := range rules {
		if strings.Contains(r, "secret.com") {
			t.Error("disabled module hostnames should be skipped")
		}
	}
	if len(rules) != 1 {
		t.Errorf("expected 1 rule, got %d: %v", len(rules), rules)
	}
}

func TestHostnameRulesEmpty(t *testing.T) {
	if rules := HostnameRules(nil); len(rules) != 0 {
		t.Errorf("expected 0 rules for nil input, got %v", rules)
	}
}

// ---------------------------------------------------------------------------
// Root CA generation and reuse
// ---------------------------------------------------------------------------

func TestGenerateRootCA(t *testing.T) {
	tmpDir := t.TempDir()

	status, err := GenerateRootCA(tmpDir)
	if err != nil {
		t.Fatalf("GenerateRootCA() failed: %v", err)
	}
	if !status.Exists {
		t.Error("status.Exists should be true")
	}
	if status.Fingerprint == "" {
		t.Error("status.Fingerprint should not be empty")
	}
	if status.ExpiresAt.IsZero() {
		t.Error("status.ExpiresAt should not be zero")
	}
	if status.PEMPath == "" {
		t.Error("status.PEMPath should not be empty")
	}

	// Verify the files exist
	certPath := caCertPath(tmpDir)
	keyPath := caKeyPath(tmpDir)
	if _, err := os.Stat(certPath); err != nil {
		t.Errorf("ca.crt not found at %s: %v", certPath, err)
	}
	if _, err := os.Stat(keyPath); err != nil {
		t.Errorf("ca.key not found at %s: %v", keyPath, err)
	}
	t.Logf("CA fingerprint: %s", status.Fingerprint)
	t.Logf("CA expires: %s", status.ExpiresAt.Format("2006-01-02"))
}

func TestGenerateRootCAReuse(t *testing.T) {
	tmpDir := t.TempDir()

	first, err := GenerateRootCA(tmpDir)
	if err != nil {
		t.Fatalf("first GenerateRootCA failed: %v", err)
	}
	second, err := GenerateRootCA(tmpDir)
	if err != nil {
		t.Fatalf("second GenerateRootCA failed: %v", err)
	}

	if first.Fingerprint != second.Fingerprint {
		t.Errorf("fingerprint changed between calls: %s vs %s",
			first.Fingerprint, second.Fingerprint)
	}
	t.Log("CA correctly reused on second call")
}

func TestGetRootCAStatusMissing(t *testing.T) {
	tmpDir := t.TempDir()
	status := GetRootCAStatus(tmpDir)
	if status != nil {
		t.Errorf("expected nil for missing CA, got: %+v", status)
	}
}

func TestGetRootCAStatusAfterGenerate(t *testing.T) {
	tmpDir := t.TempDir()

	if _, err := GenerateRootCA(tmpDir); err != nil {
		t.Fatalf("GenerateRootCA failed: %v", err)
	}
	status := GetRootCAStatus(tmpDir)
	if status == nil {
		t.Fatal("expected non-nil status after CA generation")
	}
	if !status.Exists {
		t.Error("status.Exists should be true")
	}
}

func TestExportRootCAPEM(t *testing.T) {
	tmpDir := t.TempDir()

	if _, err := GenerateRootCA(tmpDir); err != nil {
		t.Fatalf("GenerateRootCA failed: %v", err)
	}
	pem, err := ExportRootCAPEM(tmpDir)
	if err != nil {
		t.Fatalf("ExportRootCAPEM failed: %v", err)
	}
	if !strings.Contains(string(pem), "-----BEGIN CERTIFICATE-----") {
		t.Error("expected PEM-encoded certificate")
	}
	t.Logf("exported PEM (%d bytes)", len(pem))
}

func TestExportRootCAPEMMissing(t *testing.T) {
	tmpDir := t.TempDir()
	_, err := ExportRootCAPEM(tmpDir)
	if err == nil {
		t.Fatal("expected error when CA does not exist")
	}
	t.Logf("correct error: %v", err)
}

// ---------------------------------------------------------------------------
// Full runtime flow: Engine + Config injection simulation
// ---------------------------------------------------------------------------

// TestRuntimeConfigInjectionFlow simulates the full F1 verification:
// 1. Start engine → get actual port
// 2. Confirm hostnames would be converted to correct rules
// 3. Confirm the injected config fragment looks correct
// 4. Confirm engine receives CONNECT for a "MITM hostname"
func TestRuntimeConfigInjectionFlow(t *testing.T) {
	// 1. Start engine
	e := NewEngine(0)
	if err := e.Start(); err != nil {
		t.Fatalf("Start() failed: %v", err)
	}
	defer e.Stop()
	port := e.Port()
	t.Logf("step 1: MITM engine running on port %d", port)

	// 2. Hostname → rules conversion
	testModules := []ModuleRecord{
		{
			Enabled:       true,
			MITMHostnames: []string{"example.com", "*.example.org", ".test.local"},
		},
	}
	rules := HostnameRules(testModules)
	expected := []string{
		"DOMAIN,example.com,_mitm_engine",
		"DOMAIN-SUFFIX,example.org,_mitm_engine",
		"DOMAIN-SUFFIX,test.local,_mitm_engine",
	}
	for i, r := range expected {
		if i >= len(rules) || rules[i] != r {
			t.Errorf("step 2: rule[%d] = %q, want %q", i, rules[i], r)
		}
	}
	t.Logf("step 2: hostname rules: %v", rules)

	// 3. Verify what the config proxy entry would look like
	wantEntry := fmt.Sprintf(
		"  - name: _mitm_engine\n    type: http\n    server: 127.0.0.1\n    port: %d",
		port)
	t.Logf("step 3: expected proxy entry in config:\n%s", wantEntry)
	// (Actual YAML injection is exercised in Dart injectFromLists tests)

	// 4. CONNECT to engine to simulate MITM hostname routing
	// (Same as TestEngineConnectPassthrough but logging the "domain")
	targetHost := "example.com:443"
	proxyAddr := fmt.Sprintf("127.0.0.1:%d", port)
	conn, err := net.DialTimeout("tcp", proxyAddr, 2*time.Second)
	if err != nil {
		t.Fatalf("step 4: dial proxy failed: %v", err)
	}
	defer conn.Close()

	connectReq := fmt.Sprintf(
		"CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", targetHost, targetHost)
	conn.Write([]byte(connectReq))

	buf := make([]byte, 256)
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, _ := conn.Read(buf)
	resp := string(buf[:n])

	if !strings.Contains(resp, "200") {
		t.Fatalf("step 4: expected 200, got: %s", resp)
	}
	t.Logf("step 4: CONNECT %s → 200 Connection Established ✓", targetHost)

	// 5. Engine status is still consistent
	status := e.Status()
	if !status.Running || status.Port != port {
		t.Errorf("step 5: status inconsistent: %+v", status)
	}

	// 6. Stop and verify rollback
	if err := e.Stop(); err != nil {
		t.Fatalf("step 6: Stop() failed: %v", err)
	}
	if e.IsRunning() {
		t.Error("step 6: engine still running after Stop()")
	}
	t.Log("step 6: engine stopped, port released ✓")

	// Verify port is released
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Logf("step 6: port %d not yet released (OS TIME_WAIT, acceptable)", port)
	} else {
		ln.Close()
		t.Logf("step 6: port %d confirmed released ✓", port)
	}
}

// ---------------------------------------------------------------------------
// CertStatusToRootCAStatus JSON tag verification
// ---------------------------------------------------------------------------

func TestCertStatusToRootCAStatusJSONTags(t *testing.T) {
	tmpDir := t.TempDir()
	cs, err := GenerateRootCA(tmpDir)
	if err != nil {
		t.Fatalf("GenerateRootCA failed: %v", err)
	}
	rootCA := CertStatusToRootCAStatus(cs)
	data, err := json.Marshal(rootCA)
	if err != nil {
		t.Fatalf("json.Marshal failed: %v", err)
	}

	var m map[string]interface{}
	json.Unmarshal(data, &m)

	// Verify all keys Dart relies on are present with the right names
	requiredKeys := []string{"exists", "fingerprint", "created_at", "expires_at", "export_path"}
	for _, key := range requiredKeys {
		if _, ok := m[key]; !ok {
			t.Errorf("expected JSON key %q not found in: %s", key, data)
		}
	}
	t.Logf("JSON: %s", data)
}

// ---------------------------------------------------------------------------
// mitmDir path helper
// ---------------------------------------------------------------------------

func TestMitmDir(t *testing.T) {
	dir := mitmDir("/home/user/yuelink")
	want := filepath.Join("/home/user/yuelink", "mitm")
	if dir != want {
		t.Errorf("mitmDir = %q, want %q", dir, want)
	}
}
