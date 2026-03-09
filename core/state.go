package main

import "sync"

// CoreState holds the global runtime state of the mihomo core.
type CoreState struct {
	mu        sync.Mutex
	isInit    bool
	isRunning bool
	homeDir   string
}

var state = &CoreState{}

func (s *CoreState) lock()   { s.mu.Lock() }
func (s *CoreState) unlock() { s.mu.Unlock() }
