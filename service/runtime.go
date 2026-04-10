package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type ServiceRuntime struct {
	cfg *Config

	opMu sync.Mutex
	mu   sync.Mutex

	child     *exec.Cmd
	childDone chan struct{}
	pid       int

	homeDir    string
	configPath string
	logPath    string
	startedAt  time.Time
	lastExit   string
	lastError  string

	// Watchdog: auto-restart on unexpected exit
	lastStartReq   startRequest // cached for restart
	watchdogCancel context.CancelFunc
	crashCount     int
	crashWindowEnd time.Time
}

func NewServiceRuntime(cfg *Config) (*ServiceRuntime, error) {
	return &ServiceRuntime{cfg: cfg}, nil
}

func (s *ServiceRuntime) Run(ctx context.Context) error {
	server := &http.Server{
		Addr:    fmt.Sprintf("%s:%d", s.cfg.ListenHost, s.cfg.ListenPort),
		Handler: s.newHandler(),
	}

	listener, err := net.Listen("tcp", server.Addr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", server.Addr, err)
	}

	go func() {
		<-ctx.Done()
		s.opMu.Lock()
		if err := s.stopCurrentProcessLocked(); err != nil {
			log.Printf("[service] stop child during shutdown: %v", err)
		}
		s.opMu.Unlock()

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	log.Printf("[service] listening on http://%s", server.Addr)
	err = server.Serve(listener)
	if err == nil || errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func (s *ServiceRuntime) startMihomo(req startRequest) (statusResponse, error) {
	if req.ConfigYAML == "" {
		return statusResponse{}, fmt.Errorf("missing config_yaml")
	}
	if req.HomeDir == "" {
		return statusResponse{}, fmt.Errorf("missing home_dir")
	}

	s.opMu.Lock()
	defer s.opMu.Unlock()

	if err := s.stopCurrentProcessLocked(); err != nil {
		return statusResponse{}, err
	}

	return s.startMihomoInternal(req)
}

// startMihomoInternal does the actual start work. Caller must hold opMu.
func (s *ServiceRuntime) startMihomoInternal(req startRequest) (statusResponse, error) {
	if err := os.MkdirAll(req.HomeDir, 0o755); err != nil {
		return statusResponse{}, fmt.Errorf("mkdir home_dir: %w", err)
	}

	configPath := filepath.Join(req.HomeDir, "yuelink-service.yaml")
	if err := os.WriteFile(configPath, []byte(req.ConfigYAML), 0o600); err != nil {
		return statusResponse{}, fmt.Errorf("write config: %w", err)
	}

	logPath := filepath.Join(req.HomeDir, "mihomo-service.log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return statusResponse{}, fmt.Errorf("open mihomo log: %w", err)
	}

	cmd := exec.Command(s.cfg.MihomoPath, "-d", req.HomeDir, "-f", configPath)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	prepareChildProcess(cmd)

	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		s.mu.Lock()
		s.lastError = err.Error()
		s.mu.Unlock()
		return statusResponse{}, fmt.Errorf("start mihomo: %w", err)
	}

	done := make(chan struct{})
	s.mu.Lock()
	s.child = cmd
	s.childDone = done
	s.pid = cmd.Process.Pid
	s.homeDir = req.HomeDir
	s.configPath = configPath
	s.logPath = logPath
	s.startedAt = time.Now().UTC()
	s.lastError = ""
	s.lastExit = ""
	s.lastStartReq = req
	s.mu.Unlock()

	// Start watchdog context for this session
	if s.watchdogCancel != nil {
		s.watchdogCancel()
	}
	wdCtx, wdCancel := context.WithCancel(context.Background())
	s.watchdogCancel = wdCancel

	go s.waitForChild(cmd, done, logFile, wdCtx)
	log.Printf("[service] started mihomo pid=%d home=%s", cmd.Process.Pid, req.HomeDir)
	return s.statusSnapshot(), nil
}

func (s *ServiceRuntime) stopMihomo() (statusResponse, error) {
	s.opMu.Lock()
	defer s.opMu.Unlock()

	err := s.stopCurrentProcessLocked()
	return s.statusSnapshot(), err
}

func (s *ServiceRuntime) stopCurrentProcessLocked() error {
	// Cancel watchdog so it doesn't auto-restart after explicit stop
	if s.watchdogCancel != nil {
		s.watchdogCancel()
		s.watchdogCancel = nil
	}

	cmd, done := s.currentChild()
	if cmd == nil || cmd.Process == nil {
		return nil
	}

	log.Printf("[service] stopping mihomo pid=%d", cmd.Process.Pid)

	if err := terminateProcess(cmd); err != nil {
		return err
	}

	select {
	case <-done:
		return nil
	case <-time.After(5 * time.Second):
		log.Printf("[service] graceful stop timed out for pid=%d, forcing kill", cmd.Process.Pid)
		if err := killProcess(cmd); err != nil {
			return err
		}
		select {
		case <-done:
			return nil
		case <-time.After(3 * time.Second):
			return fmt.Errorf("mihomo pid=%d did not exit after kill", cmd.Process.Pid)
		}
	}
}

func (s *ServiceRuntime) currentChild() (*exec.Cmd, chan struct{}) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.child, s.childDone
}

// Watchdog constants (matches CVR: max 10 crashes in 10 minutes)
const (
	watchdogMaxCrashes = 10
	watchdogWindow     = 10 * time.Minute
	watchdogBaseDelay  = 2 * time.Second
	watchdogMaxDelay   = 30 * time.Second
)

func (s *ServiceRuntime) waitForChild(cmd *exec.Cmd, done chan struct{}, logFile *os.File, wdCtx context.Context) {
	err := cmd.Wait()
	exitText := fmt.Sprintf("exited at %s", time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		exitText = fmt.Sprintf("%s (%v)", exitText, err)
	}

	s.mu.Lock()
	isCurrentChild := s.child == cmd
	if isCurrentChild {
		s.child = nil
		s.childDone = nil
		s.pid = 0
		s.lastExit = exitText
		if err != nil {
			s.lastError = err.Error()
		}
	}
	cachedReq := s.lastStartReq
	s.mu.Unlock()

	_ = logFile.Close()
	close(done)
	log.Printf("[service] mihomo %s", exitText)

	// Watchdog: auto-restart if the exit was unexpected (context not cancelled)
	if !isCurrentChild {
		return
	}
	select {
	case <-wdCtx.Done():
		log.Printf("[watchdog] explicit stop — no restart")
		return
	default:
	}

	// Crash window tracking
	now := time.Now()
	if now.After(s.crashWindowEnd) {
		s.crashCount = 0
		s.crashWindowEnd = now.Add(watchdogWindow)
	}
	s.crashCount++

	if s.crashCount > watchdogMaxCrashes {
		log.Printf("[watchdog] %d crashes in window — giving up", s.crashCount)
		return
	}

	// Exponential backoff: 2s, 4s, 8s, 16s, 30s cap
	delay := watchdogBaseDelay
	for i := 1; i < s.crashCount; i++ {
		delay *= 2
		if delay > watchdogMaxDelay {
			delay = watchdogMaxDelay
			break
		}
	}

	log.Printf("[watchdog] crash #%d — restarting in %v", s.crashCount, delay)
	select {
	case <-time.After(delay):
	case <-wdCtx.Done():
		log.Printf("[watchdog] cancelled during backoff wait")
		return
	}

	// Re-check context before restarting
	select {
	case <-wdCtx.Done():
		return
	default:
	}

	s.opMu.Lock()
	_, restartErr := s.startMihomoInternal(cachedReq)
	s.opMu.Unlock()
	if restartErr != nil {
		log.Printf("[watchdog] restart failed: %v", restartErr)
	}
}

func (s *ServiceRuntime) statusSnapshot() statusResponse {
	s.mu.Lock()
	defer s.mu.Unlock()

	var startedAt string
	if !s.startedAt.IsZero() {
		startedAt = s.startedAt.Format(time.RFC3339)
	}

	return statusResponse{
		Running:    s.child != nil && s.pid > 0,
		Pid:        s.pid,
		HomeDir:    s.homeDir,
		ConfigPath: s.configPath,
		LogPath:    s.logPath,
		StartedAt:  startedAt,
		LastExit:   s.lastExit,
		LastError:  s.lastError,
	}
}

func (s *ServiceRuntime) readLogs(lines int) logsResponse {
	s.mu.Lock()
	path := s.logPath
	s.mu.Unlock()

	content, err := tailFile(path, lines)
	if err != nil {
		return logsResponse{
			LogPath: path,
			Content: "",
			Error:   err.Error(),
		}
	}

	return logsResponse{
		LogPath: path,
		Content: content,
	}
}

func tailFile(path string, lines int) (string, error) {
	if path == "" {
		return "", nil
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	if lines <= 0 {
		return string(raw), nil
	}

	all := splitLines(string(raw))
	if len(all) <= lines {
		return string(raw), nil
	}
	return joinLines(all[len(all)-lines:]), nil
}

func splitLines(content string) []string {
	if content == "" {
		return nil
	}
	normalized := strings.ReplaceAll(content, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	return strings.Split(normalized, "\n")
}

func joinLines(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	result := lines[0]
	for _, line := range lines[1:] {
		result += "\n" + line
	}
	return result
}
