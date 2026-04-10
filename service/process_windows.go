//go:build windows

package main

import (
	"fmt"
	"os/exec"
	"syscall"
)

func prepareChildProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}

func terminateProcess(cmd *exec.Cmd) error {
	return killProcess(cmd)
}

func killProcess(cmd *exec.Cmd) error {
	if cmd.Process == nil {
		return nil
	}
	if err := cmd.Process.Kill(); err != nil && err.Error() != "os: process already finished" {
		return fmt.Errorf("kill process: %w", err)
	}
	return nil
}
