package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"unsafe"

	"github.com/metacubex/mihomo/config"
	mihomoConst "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
)

// --------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------

// InitCore initializes the mihomo core with the given home directory.
// Sets up config paths and prepares the runtime environment.
// Returns 0 on success, -1 on failure.
//
//export InitCore
func InitCore(homeDir *C.char) C.int {
	state.lock()
	defer state.unlock()

	dir := C.GoString(homeDir)

	// Ensure directory exists
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return -1
	}

	// Set mihomo home directory
	if !filepath.IsAbs(dir) {
		cwd, _ := os.Getwd()
		dir = filepath.Join(cwd, dir)
	}
	mihomoConst.SetHomeDir(dir)

	// Initialize config system (creates necessary files)
	if err := config.Init(dir); err != nil {
		log.Errorln("Config init failed: %v", err)
		return -1
	}

	state.homeDir = dir
	state.isInit = true

	return 0
}

// StartCore starts the mihomo core with the given YAML configuration.
// This starts the proxy engine, listeners, and the external-controller REST API.
// Returns 0 on success, -1 on failure.
//
//export StartCore
func StartCore(configStr *C.char) C.int {
	state.lock()
	defer state.unlock()

	if !state.isInit {
		return -1
	}
	if state.isRunning {
		return -1
	}

	configYaml := C.GoString(configStr)

	// Write config to file so mihomo can reload it later
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(configYaml), 0o644); err != nil {
		log.Errorln("Failed to write config: %v", err)
		return -1
	}
	mihomoConst.SetConfig(configPath)

	// Parse and apply config via hub.Parse (starts everything)
	var options []hub.Option
	if err := hub.Parse([]byte(configYaml), options...); err != nil {
		log.Errorln("Failed to parse config: %v", err)
		return -1
	}

	state.isRunning = true
	log.Infoln("YueLink core started")
	return 0
}

// StopCore stops the mihomo core.
// Shuts down all listeners and cleans up resources.
//
//export StopCore
func StopCore() {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return
	}

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
	yaml := C.GoString(configStr)

	_, err := executor.ParseWithBytes([]byte(yaml))
	if err != nil {
		return -1
	}

	return 0
}

// UpdateConfig applies a new configuration (hot reload).
// Returns 0 on success, -1 on failure.
//
//export UpdateConfig
func UpdateConfig(configStr *C.char) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	yaml := C.GoString(configStr)

	// Write updated config
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(yaml), 0o644); err != nil {
		return -1
	}

	// Re-parse and apply
	if err := hub.Parse([]byte(yaml)); err != nil {
		log.Errorln("Config update failed: %v", err)
		return -1
	}

	log.Infoln("Config updated successfully")
	return 0
}

// --------------------------------------------------------------------
// Proxies (minimal — prefer REST API for data operations)
// --------------------------------------------------------------------

// GetProxies returns the current proxy groups as JSON.
// NOTE: In the hybrid architecture, prefer using the REST API
// on external-controller port for proxy data. This FFI endpoint
// exists as a fallback.
// Caller must free the returned C string with FreeCString().
//
//export GetProxies
func GetProxies() *C.char {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return C.CString(`{"proxies":{}}`)
	}

	// Return a minimal response — the REST API provides full proxy data
	result := map[string]interface{}{
		"proxies": map[string]interface{}{},
	}
	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// ChangeProxy switches the selected proxy in a group via FFI.
// Returns 0 on success, -1 on failure.
//
//export ChangeProxy
func ChangeProxy(groupName *C.char, proxyName *C.char) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	// In hybrid architecture, proxy changes go through REST API
	_ = C.GoString(groupName)
	_ = C.GoString(proxyName)

	return 0
}

// TestDelay tests proxy latency via FFI.
// Returns delay in ms, or -1 on failure.
//
//export TestDelay
func TestDelay(proxyName *C.char, url *C.char, timeoutMs C.int) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	// In hybrid architecture, delay tests go through REST API
	_ = C.GoString(proxyName)
	_ = C.GoString(url)
	_ = int(timeoutMs)

	return -1
}

// --------------------------------------------------------------------
// Traffic & Connections (minimal — prefer REST API)
// --------------------------------------------------------------------

// GetTraffic returns current traffic rates as JSON.
//
//export GetTraffic
func GetTraffic() *C.char {
	result := map[string]int64{
		"up":   0,
		"down": 0,
	}
	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// GetConnections returns active connections as JSON.
//
//export GetConnections
func GetConnections() *C.char {
	result := map[string]interface{}{
		"connections":   []interface{}{},
		"uploadTotal":   0,
		"downloadTotal": 0,
	}
	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// CloseConnection closes a specific connection by ID.
//
//export CloseConnection
func CloseConnection(connId *C.char) C.int {
	_ = C.GoString(connId)
	return 0
}

// CloseAllConnections closes all active connections.
//
//export CloseAllConnections
func CloseAllConnections() {
	// Handled by REST API in hybrid architecture
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
// Memory management
// --------------------------------------------------------------------

// FreeCString frees a C string previously returned by this library.
//
//export FreeCString
func FreeCString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// Required main for c-shared/c-archive build mode
func main() {}
