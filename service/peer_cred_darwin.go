//go:build darwin

package main

import (
	"net"

	"golang.org/x/sys/unix"
)

// getPeerUID returns the connecting process's effective UID via
// LOCAL_PEERCRED (which returns a Xucred struct on macOS).
func getPeerUID(conn net.Conn) (uint32, bool) {
	uc, ok := conn.(*net.UnixConn)
	if !ok {
		return 0, false
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return 0, false
	}
	var uid uint32
	var got bool
	_ = raw.Control(func(fd uintptr) {
		xucred, err := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if err == nil && xucred != nil {
			uid = xucred.Uid
			got = true
		}
	})
	return uid, got
}
