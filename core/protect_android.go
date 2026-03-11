//go:build android

package main

/*
#include <stdlib.h>

// Defined in protect_android.c
extern int protect_fd(int fd);
*/
import "C"

import (
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/log"
)

func init() {
	// Set the socket protection hook for Android VPN.
	//
	// Every outbound socket mihomo creates (proxy connections, DNS queries,
	// etc.) goes through this hook. protect_fd() calls VpnService.protect(fd)
	// via JNI, which marks the socket to bypass VPN routing.
	//
	// Without this, outbound sockets may loop back through the TUN interface,
	// creating a routing loop where nothing reaches the internet.
	//
	// When DefaultSocketHook is set, mihomo's dialer skips interfaceName and
	// routingMark binding — protect() is the sole routing mechanism.
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		err := conn.Control(func(fd uintptr) {
			ok := C.protect_fd(C.int(fd))
			if ok == 0 {
				log.Warnln("[Protect] failed to protect fd %d for %s -> %s", fd, network, address)
			}
		})
		return err
	}
	log.Infoln("[Protect] Android socket protection hook installed")
}

// notifyDnsChangedFromC is called from C (protect_android.c) when the
// Android network changes and new DNS servers are detected.
//
// Mirrors CMFA's NetworkObserveModule → notifyDnsChanged flow:
// flush DNS cache and reset resolver connections so stale entries
// from the old network don't cause resolution failures.
//
//export notifyDnsChangedFromC
func notifyDnsChangedFromC(dnsList *C.char) {
	servers := C.GoString(dnsList)
	log.Infoln("[DNS] system DNS changed: %s", servers)
	resolver.ClearCache()
	resolver.ResetConnection()
}
