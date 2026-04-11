package main

import (
	"encoding/json"
	"net/http"
	"strconv"
)

// startRequest is the body of POST /v1/start. It NO LONGER carries raw
// config content — only validated absolute paths to a home directory and
// a pre-written config file. The client (running as the user) writes the
// config file first, then calls start with the path.
type startRequest struct {
	HomeDir    string `json:"home_dir"`
	ConfigPath string `json:"config_path"`
}

type statusResponse struct {
	Running    bool   `json:"running"`
	Pid        int    `json:"pid"`
	HomeDir    string `json:"home_dir,omitempty"`
	ConfigPath string `json:"config_path,omitempty"`
	LogPath    string `json:"log_path,omitempty"`
	StartedAt  string `json:"started_at,omitempty"`
	LastExit   string `json:"last_exit,omitempty"`
	LastError  string `json:"last_error,omitempty"`
}

type logsResponse struct {
	LogPath string `json:"log_path,omitempty"`
	Content string `json:"content,omitempty"`
	Error   string `json:"error,omitempty"`
}

type errorResponse struct {
	Error string `json:"error"`
}

// newHandler builds the HTTP routing tree shared by both transports
// (Unix-socket on macOS/Linux, HTTP-loopback on Windows). Auth is enforced
// at the transport layer:
//   - Unix socket: getpeereid → reject if peer UID != cfg.OwnerUID
//   - HTTP loopback (Windows): bearer token check via withTokenAuth
//
// Either way, by the time a handler runs the caller is authenticated as the
// installer user. Path validation runs INSIDE each handler that touches
// the filesystem so the allowlist is the last line of defense.
func (s *ServiceRuntime) newHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/ping", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	})
	mux.HandleFunc("/v1/version", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"version": Version})
	})
	mux.HandleFunc("/v1/status", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, s.statusSnapshot())
	})
	mux.HandleFunc("/v1/start", func(w http.ResponseWriter, r *http.Request) {
		var req startRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		status, err := s.startMihomo(req)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, status)
	})
	mux.HandleFunc("/v1/stop", func(w http.ResponseWriter, _ *http.Request) {
		status, err := s.stopMihomo()
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, status)
	})
	mux.HandleFunc("/v1/logs", func(w http.ResponseWriter, r *http.Request) {
		lines, _ := strconv.Atoi(r.URL.Query().Get("lines"))
		if lines <= 0 {
			lines = 200
		}
		writeJSON(w, http.StatusOK, s.readLogs(lines))
	})
	return mux
}

// withTokenAuth wraps a handler with bearer token authentication. Used by
// the Windows HTTP transport (Unix socket has getpeereid instead).
func (s *ServiceRuntime) withTokenAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.cfg.Token == "" || r.Header.Get("X-YueLink-Token") != s.cfg.Token {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}
