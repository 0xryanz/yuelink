//go:build !windows

package main

import (
	"fmt"
	"os/exec"
	"syscall"
)

func prepareChildProcess(cmd *exec.Cmd) {}

func terminateProcess(cmd *exec.Cmd) error {
	if cmd.Process == nil {
		return nil
	}
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil && err.Error() != "os: process already finished" {
		return fmt.Errorf("terminate process: %w", err)
	}
	return nil
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
