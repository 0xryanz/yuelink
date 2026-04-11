//go:build linux

package main

import (
	"net"

	"golang.org/x/sys/unix"
)

// getPeerUID returns the connecting process's effective UID via SO_PEERCRED.
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
		ucred, err := unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
		if err == nil && ucred != nil {
			uid = ucred.Uid
			got = true
		}
	})
	return uid, got
}
