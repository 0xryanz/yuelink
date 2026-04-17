package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
	"unsafe"

	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	mihomoConst "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/user/yuelink/core/mitm"

	logrus "github.com/sirupsen/logrus"
)

// --------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------

// InitCore initializes the mihomo core with the given home directory.
// Sets up config paths and prepares the runtime environment.
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export InitCore
func InitCore(homeDir *C.char) (result *C.char) {
	// Recover from Go panics — a panic in CGO kills the entire Flutter process.
	// Uses named return so the deferred recover can set the error string.
	defer func() {
		if r := recover(); r != nil {
			log.Errorln("[InitCore] PANIC recovered: %v", r)
			result = C.CString(fmt.Sprintf("PANIC: %v", r))
		}
	}()

	state.lock()
	defer state.unlock()

	dir := C.GoString(homeDir)

	// Ensure directory exists
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return C.CString(fmt.Sprintf("MkdirAll failed: %v", err))
	}

	// Set mihomo home directory
	if !filepath.IsAbs(dir) {
		cwd, _ := os.Getwd()
		dir = filepath.Join(cwd, dir)
	}
	mihomoConst.SetHomeDir(dir)

	// Set config file to absolute path BEFORE config.Init()
	// (config.Init uses C.Path.Config() which defaults to relative "config.yaml",
	// causing file creation failures on Android where cwd is not writable)
	mihomoConst.SetConfig(filepath.Join(dir, "config.yaml"))

	// Initialize config system (creates necessary files)
	if err := config.Init(dir); err != nil {
		return C.CString(fmt.Sprintf("config.Init failed: %v", err))
	}

	// Close previous log file handle if re-initializing (prevents fd leak)
	if state.logFile != nil {
		state.logFile.Close()
		state.logFile = nil
	}

	// Redirect logrus output to core.log so Dart can read Go-side logs.
	// Also tee to stdout for adb logcat / Xcode console.
	// Log rotation: keep at most `core.log` + `.1` + `.2` (~15 MB total).
	// Was: O_TRUNC on every InitCore — correct for disk cap, wrong for
	// diagnosability (a crash's Go panic got wiped on auto-restart).
	// Now: rotate if current size exceeds 5 MB, append otherwise.
	logPath := filepath.Join(dir, "core.log")
	rotateLogFile(logPath, 5*1024*1024, 3)
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err == nil {
		state.logFile = logFile
		logrus.SetOutput(io.MultiWriter(os.Stdout, logFile))
	}

	log.Infoln("[BOOT] InitCore OK, homeDir=%s", dir)

	state.homeDir = dir
	state.isInit = true

	return C.CString("")
}

// rotateLogFile rotates `path` → `path.1` → `path.2` … → `path.(backups-1)`
// when the current file exceeds maxBytes. Older ones get discarded by the
// shift. No-op if the file is missing or still small enough.
//
// Tiny hand-rolled rotation so we don't pull lumberjack (would bloat the
// static library 1 MB+ on mobile for a single feature). Rotation only
// happens at InitCore time; within a single long session the live file
// can grow past maxBytes until the next restart — acceptable because
// the VPN core typically churns on Wi-Fi switches / OS sleeps anyway.
func rotateLogFile(path string, maxBytes int64, backups int) {
	info, err := os.Stat(path)
	if err != nil || info.Size() <= maxBytes {
		return
	}
	for i := backups - 1; i >= 1; i-- {
		src := fmt.Sprintf("%s.%d", path, i)
		dst := fmt.Sprintf("%s.%d", path, i+1)
		_ = os.Rename(src, dst) // silent if src is missing; overwrite dst
	}
	_ = os.Rename(path, path+".1")
}

// StartCore starts the mihomo core with the given YAML configuration.
// This starts the proxy engine, listeners, and the external-controller REST API.
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export StartCore
func StartCore(configStr *C.char) (result *C.char) {
	state.lock()
	defer state.unlock()

	// Recover from Go panics — a panic in CGO kills the entire Flutter process.
	// Uses named return so the deferred recover can set the error string.
	defer func() {
		if r := recover(); r != nil {
			log.Errorln("[StartCore] PANIC recovered: %v", r)
			state.isRunning = false
			result = C.CString(fmt.Sprintf("PANIC: %v", r))
		}
	}()

	if !state.isInit {
		return C.CString("core not initialized, call InitCore first")
	}
	if state.isRunning {
		return C.CString("")
	}

	configYaml := C.GoString(configStr)
	log.Infoln("[CORE] StartCore called, configLen=%d", len(configYaml))

	// Write config to file so mihomo can reload it later
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(configYaml), 0o644); err != nil {
		log.Errorln("[CORE] write config failed: %v", err)
		return C.CString(fmt.Sprintf("write config: %v", err))
	}
	mihomoConst.SetConfig(configPath)
	log.Infoln("[CORE] config written to %s", configPath)

	// Log key config sections for diagnostics
	logConfigDiag(configYaml)

	// Parse and apply config via hub.Parse (starts everything: proxies, rules,
	// DNS, external-controller REST API, TUN listener, etc.).
	// Returns an error if the config YAML is invalid, geo files are missing,
	// or any critical listener fails to start.
	log.Infoln("[CORE] calling hub.Parse()...")
	if err := hub.Parse([]byte(configYaml)); err != nil {
		log.Errorln("[CORE] hub.Parse failed: %v", err)
		return C.CString(fmt.Sprintf("parse config: %v", err))
	}
	log.Infoln("[CORE] hub.Parse OK")

	// Post-startup diagnostics (pass the actual external-controller address)
	ecAddr := "127.0.0.1:9090"
	if m := regexp.MustCompile(`(?m)^external-controller:\s*(.+)$`).FindStringSubmatch(configYaml); len(m) > 1 {
		ecAddr = strings.TrimSpace(m[1])
	}
	logPostStartDiag(ecAddr)

	state.isRunning = true
	log.Infoln("[CORE] YueLink core started successfully")
	return C.CString("")
}

// StopCore stops the mihomo core.
// Shuts down all listeners and cleans up resources.
//
//export StopCore
func StopCore() {
	state.lock()
	defer state.unlock()

	defer func() {
		if r := recover(); r != nil {
			log.Errorln("[StopCore] PANIC recovered: %v", r)
		}
	}()

	if !state.isRunning {
		return
	}

	log.Infoln("[StopCore] shutting down...")
	executor.Shutdown()
	state.isRunning = false
	log.Infoln("YueLink core stopped")
}

// Shutdown fully shuts down and cleans up the core.
//
//export Shutdown
func Shutdown() {
	StopCore()
	state.lock()
	defer state.unlock()
	state.isInit = false
}

// IsRunning returns 1 if the core is running, 0 otherwise.
//
//export IsRunning
func IsRunning() C.int {
	state.lock()
	defer state.unlock()
	if state.isRunning {
		return 1
	}
	return 0
}

// --------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------

// ValidateConfig checks if the given YAML config is valid.
// Returns 0 if valid, -1 if invalid.
//
//export ValidateConfig
func ValidateConfig(configStr *C.char) C.int {
	state.lock()
	defer state.unlock()

	yaml := C.GoString(configStr)

	_, err := executor.ParseWithBytes([]byte(yaml))
	if err != nil {
		return -1
	}

	return 0
}

// UpdateConfig applies a new configuration (hot reload).
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export UpdateConfig
func UpdateConfig(configStr *C.char) *C.char {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return C.CString("core not running")
	}

	yaml := C.GoString(configStr)

	// Write updated config
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(yaml), 0o644); err != nil {
		return C.CString(fmt.Sprintf("write config: %v", err))
	}

	// Re-parse and apply
	if err := hub.Parse([]byte(yaml)); err != nil {
		return C.CString(fmt.Sprintf("parse config: %v", err))
	}

	log.Infoln("Config updated successfully")
	return C.CString("")
}

// --------------------------------------------------------------------
// Version
// --------------------------------------------------------------------

// GetVersion returns the mihomo version string.
// Caller must free the returned C string.
//
//export GetVersion
func GetVersion() *C.char {
	v := fmt.Sprintf("mihomo Meta %s", mihomoConst.Version)
	return C.CString(v)
}

// --------------------------------------------------------------------
// MITM Engine
// --------------------------------------------------------------------

// StartMITMEngine starts the MITM proxy engine singleton on the default port
// (9091), falling back to an OS-assigned port if 9091 is busy.
// Returns empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export StartMITMEngine
func StartMITMEngine() (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			result = C.CString(fmt.Sprintf("PANIC: %v", r))
		}
	}()
	state.lock()
	defer state.unlock()

	if err := mitm.StartMITMEngine(0); err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}

// UpdateMITMConfig applies a Phase-2 interception configuration to the running
// MITM engine. configJSON must be a JSON-encoded MITMConfig
// ({"hostnames":[...],"url_rewrites":[...],"header_rewrites":[...]}).
// Returns empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export UpdateMITMConfig
func UpdateMITMConfig(configJSON *C.char) (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			result = C.CString(fmt.Sprintf("PANIC: %v", r))
		}
	}()
	state.lock()
	defer state.unlock()

	if !state.isInit {
		return C.CString("core not initialized, call InitCore first")
	}

	jsonStr := C.GoString(configJSON)
	var cfg mitm.MITMConfig
	if err := json.Unmarshal([]byte(jsonStr), &cfg); err != nil {
		return C.CString(fmt.Sprintf("invalid MITMConfig JSON: %v", err))
	}

	if err := mitm.ConfigureMITMEngine(state.homeDir, cfg); err != nil {
		return C.CString(err.Error())
	}
	log.Infoln("[MITM] config updated: %d hosts, %d URL rules, %d header rules",
		len(cfg.Hostnames), len(cfg.URLRewrites), len(cfg.HeaderRewrites))
	return C.CString("")
}

// StopMITMEngine stops the MITM proxy engine singleton.
// Returns empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export StopMITMEngine
func StopMITMEngine() (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			result = C.CString(fmt.Sprintf("PANIC: %v", r))
		}
	}()
	state.lock()
	defer state.unlock()

	if err := mitm.StopMITMEngine(); err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}

// GetMITMEngineStatus returns the current MITM engine status as a JSON string.
// JSON shape: {"running":bool,"port":int,"address":"...","started_at":"...","healthy":bool,"last_error":"..."}
// Returns "{}" on marshal error.
// Caller must free the returned string via FreeCString.
// Note: no state lock needed — GetMITMEngineStatus is internally synchronized.
//
//export GetMITMEngineStatus
func GetMITMEngineStatus() (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			result = C.CString("{}")
		}
	}()

	status := mitm.GetMITMEngineStatus()
	data, err := json.Marshal(status)
	if err != nil {
		return C.CString("{}")
	}
	return C.CString(string(data))
}

// GenerateRootCA generates (or reuses) the MITM Root CA certificate.
// Stores key material under <homeDir>/mitm/.
// Returns JSON of RootCAStatus on success, or {"error":"..."} on failure.
// Caller must free the returned string via FreeCString.
//
//export GenerateRootCA
func GenerateRootCA() (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			errJSON := fmt.Sprintf(`{"error":"PANIC: %v"}`, r)
			result = C.CString(errJSON)
		}
	}()
	state.lock()
	defer state.unlock()

	if !state.isInit {
		return C.CString(`{"error":"core not initialized, call InitCore first"}`)
	}

	caStatus, err := mitm.GenerateRootCA(state.homeDir)
	if err != nil {
		errJSON := fmt.Sprintf(`{"error":"%s"}`, jsonEscapeString(err.Error()))
		return C.CString(errJSON)
	}
	rootStatus := mitm.CertStatusToRootCAStatus(caStatus)
	data, err := json.Marshal(rootStatus)
	if err != nil {
		return C.CString(`{"error":"failed to marshal CA status"}`)
	}
	return C.CString(string(data))
}

// GetRootCAStatus returns the current Root CA status as a JSON string.
// JSON shape: RootCAStatus (see types.go).
// Returns "{}" if the CA does not exist or is invalid.
// Caller must free the returned string via FreeCString.
//
//export GetRootCAStatus
func GetRootCAStatus() (result *C.char) {
	defer func() {
		if r := recover(); r != nil {
			result = C.CString("{}")
		}
	}()
	state.lock()
	defer state.unlock()

	if !state.isInit {
		return C.CString("{}")
	}

	cs := mitm.GetRootCAStatus(state.homeDir)
	rootStatus := mitm.CertStatusToRootCAStatus(cs) // handles nil cs safely
	data, err := json.Marshal(rootStatus)
	if err != nil {
		return C.CString("{}")
	}
	return C.CString(string(data))
}

// jsonEscapeString escapes a string for safe embedding in a JSON string literal.
// Handles backslash, double-quote, and common control characters.
func jsonEscapeString(s string) string {
	b, err := json.Marshal(s)
	if err != nil {
		return "unknown error"
	}
	// json.Marshal wraps in quotes; strip them.
	if len(b) >= 2 {
		return string(b[1 : len(b)-1])
	}
	return string(b)
}

// --------------------------------------------------------------------
// Memory management
// --------------------------------------------------------------------

// FreeCString frees a C string previously returned by this library.
//
//export FreeCString
func FreeCString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// --------------------------------------------------------------------
// Diagnostics
// --------------------------------------------------------------------

// logConfigDiag logs key sections of the config YAML for debugging.
func logConfigDiag(yaml string) {
	// Log external-controller address — critical for REST API availability
	reEC := regexp.MustCompile(`(?m)^external-controller:\s*(.+)$`)
	if m := reEC.FindStringSubmatch(yaml); len(m) > 1 {
		log.Infoln("[Diag] external-controller: %s", strings.TrimSpace(m[1]))
	} else {
		log.Errorln("[Diag] No external-controller in config — REST API will NOT start!")
	}

	// Log TUN section
	if idx := strings.Index(yaml, "\ntun:"); idx >= 0 {
		end := findSectionEnd(yaml, idx+1)
		log.Infoln("[Diag] TUN config:\n%s", yaml[idx+1:end])
	} else {
		log.Warnln("[Diag] No TUN section found in config!")
	}

	// Log DNS enable status
	if idx := strings.Index(yaml, "\ndns:"); idx >= 0 {
		end := findSectionEnd(yaml, idx+1)
		section := yaml[idx+1 : end]
		if strings.Contains(section, "enable: true") {
			log.Infoln("[Diag] DNS enabled")
		} else if strings.Contains(section, "enable: false") {
			log.Warnln("[Diag] DNS DISABLED in config!")
		} else {
			log.Warnln("[Diag] DNS enable status unclear")
		}
		// Log first 200 chars of DNS section
		if len(section) > 200 {
			section = section[:200] + "..."
		}
		log.Infoln("[Diag] DNS config:\n%s", section)
	} else {
		log.Warnln("[Diag] No DNS section found in config!")
	}
}

// findSectionEnd finds where a YAML top-level section ends.
func findSectionEnd(yaml string, start int) int {
	lines := strings.Split(yaml[start:], "\n")
	pos := start
	for i, line := range lines {
		if i == 0 {
			pos += len(line) + 1
			continue
		}
		if len(line) > 0 && line[0] != ' ' && line[0] != '\t' && line[0] != '#' {
			break
		}
		pos += len(line) + 1
	}
	if pos > len(yaml) {
		pos = len(yaml)
	}
	return pos
}

// logPostStartDiag logs the state of key subsystems after startup.
// ecAddr is the external-controller address from the config (e.g. "127.0.0.1:9090").
func logPostStartDiag(ecAddr string) {
	// Check DNS resolver
	if resolver.DefaultResolver != nil {
		log.Infoln("[Diag] DNS DefaultResolver: initialized")
	} else {
		log.Errorln("[Diag] DNS DefaultResolver: NIL — DNS resolution will fail!")
	}
	if resolver.DefaultService != nil {
		log.Infoln("[Diag] DNS DefaultService: initialized")
	} else {
		log.Errorln("[Diag] DNS DefaultService: NIL — DNS hijack relay will fail!")
	}

	// Check TUN listener
	tunConf := listener.LastTunConf
	log.Infoln("[Diag] TUN enabled=%v fd=%d stack=%s dns-hijack=%v",
		tunConf.Enable, tunConf.FileDescriptor, tunConf.Stack, tunConf.DNSHijack)

	// Verify external-controller port is actually listening.
	// hub.Parse starts it in a goroutine; probe after a short settle time
	// to catch silent bind failures (port in use, permission denied, etc.).
	// Runs in a goroutine because StartCore holds the state lock — we must
	// not block here, and the probe is diagnostic-only (does not affect startup).
	go func() {
		// Give route.ReCreateServer 500ms to bind the listening socket.
		time.Sleep(500 * time.Millisecond)
		conn, err := net.DialTimeout("tcp", ecAddr, 2*time.Second)
		if err != nil {
			log.Errorln("[Diag] external-controller %s NOT reachable after 500ms: %v", ecAddr, err)
			log.Errorln("[Diag] REST API unavailable — Dart waitApi will time out!")
		} else {
			conn.Close()
			log.Infoln("[Diag] external-controller %s is listening OK", ecAddr)
		}
	}()
}

// Required main for c-shared/c-archive build mode
func main() {}
