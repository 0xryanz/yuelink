//go:build !windows

package main

func isWindowsService() (bool, error) {
	return false, nil
}

func runWindowsService(_ string) error {
	return nil
}
