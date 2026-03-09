package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"unsafe"
)

// --------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------

// InitCore initializes the mihomo core with the given home directory.
// Returns 0 on success, -1 on failure.
//
//export InitCore
func InitCore(homeDir *C.char) C.int {
	state.lock()
	defer state.unlock()

	dir := C.GoString(homeDir)
	state.homeDir = dir
	state.isInit = true

	// TODO: Initialize mihomo filesystem paths
	// constant.SetHomeDir(dir)
	// constant.SetConfig("")

	return 0
}

// StartCore starts the mihomo core with the given YAML configuration.
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

	_ = C.GoString(configStr)

	// TODO: Parse config and start mihomo
	// rawCfg, err := config.UnmarshalRawConfig([]byte(configYaml))
	// if err != nil { return -1 }
	// cfg, err := config.ParseRawConfig(rawCfg)
	// if err != nil { return -1 }
	// hub.ApplyConfig(cfg, true)

	state.isRunning = true
	return 0
}

// StopCore stops the mihomo core.
//
//export StopCore
func StopCore() {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return
	}

	// TODO: Stop mihomo
	// tunnel.DefaultManager.ResetStatistic()
	// listener.CloseAll()

	state.isRunning = false
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
	_ = C.GoString(configStr)

	// TODO: Validate config
	// _, err := config.UnmarshalRawConfig([]byte(yaml))
	// if err != nil { return -1 }

	return 0
}

// UpdateConfig applies a partial configuration update without full restart.
// Returns 0 on success, -1 on failure.
//
//export UpdateConfig
func UpdateConfig(configStr *C.char) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	_ = C.GoString(configStr)

	// TODO: Apply partial config update
	// hub.ApplyConfig(cfg, false)

	return 0
}

// --------------------------------------------------------------------
// Proxies
// --------------------------------------------------------------------

// GetProxies returns the current proxy groups and nodes as a JSON string.
// Caller must free the returned C string with C.free().
//
//export GetProxies
func GetProxies() *C.char {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return C.CString("{}")
	}

	// TODO: Get proxies from tunnel
	// proxies := tunnel.Proxies()
	// Convert to JSON

	result := map[string]interface{}{
		"proxies": []interface{}{},
	}
	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// ChangeProxy switches the selected proxy in a proxy group.
// Returns 0 on success, -1 on failure.
//
//export ChangeProxy
func ChangeProxy(groupName *C.char, proxyName *C.char) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	_ = C.GoString(groupName)
	_ = C.GoString(proxyName)

	// TODO: Change proxy
	// proxies := tunnel.Proxies()
	// group, ok := proxies[name]
	// adapter.URLTest.SelectProxy(proxyName)

	return 0
}

// TestDelay tests the latency of a proxy node.
// Returns the delay in milliseconds, or -1 on failure.
//
//export TestDelay
func TestDelay(proxyName *C.char, url *C.char, timeoutMs C.int) C.int {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return -1
	}

	_ = C.GoString(proxyName)
	_ = C.GoString(url)
	_ = int(timeoutMs)

	// TODO: Test delay
	// proxy := tunnel.Proxies()[name]
	// delay, err := proxy.URLTest(ctx, url)

	return -1
}

// --------------------------------------------------------------------
// Traffic & Connections
// --------------------------------------------------------------------

// GetTraffic returns the current upload/download traffic rates as JSON.
// Format: {"up": 1234, "down": 5678} (bytes per second)
// Caller must free the returned C string.
//
//export GetTraffic
func GetTraffic() *C.char {
	result := map[string]int64{
		"up":   0,
		"down": 0,
	}

	// TODO: Get traffic from statistic manager
	// snap := statistic.DefaultManager.Snapshot()
	// result["up"] = snap.UploadTotal
	// result["down"] = snap.DownloadTotal

	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// GetConnections returns all active connections as JSON.
// Caller must free the returned C string.
//
//export GetConnections
func GetConnections() *C.char {
	result := map[string]interface{}{
		"connections":   []interface{}{},
		"uploadTotal":   0,
		"downloadTotal": 0,
	}

	// TODO: Get connections
	// snap := statistic.DefaultManager.Snapshot()

	data, _ := json.Marshal(result)
	return C.CString(string(data))
}

// CloseConnection closes a specific connection by its ID.
// Returns 0 on success, -1 if not found.
//
//export CloseConnection
func CloseConnection(connId *C.char) C.int {
	_ = C.GoString(connId)

	// TODO: Close connection
	// statistic.DefaultManager.Close(id)

	return 0
}

// CloseAllConnections closes all active connections.
//
//export CloseAllConnections
func CloseAllConnections() {
	// TODO: Close all
	// statistic.DefaultManager.CloseAll()
}

// --------------------------------------------------------------------
// Memory management
// --------------------------------------------------------------------

// FreeCString frees a C string previously returned by this library.
// Must be called from Dart side after reading the string.
//
//export FreeCString
func FreeCString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// --------------------------------------------------------------------
// Required main
// --------------------------------------------------------------------

func main() {}
