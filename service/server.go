package main

import (
	"encoding/json"
	"net/http"
	"strconv"
)

type startRequest struct {
	ConfigYAML string `json:"config_yaml"`
	HomeDir    string `json:"home_dir"`
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

func (s *ServiceRuntime) newHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/ping", s.withAuth(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("/v1/version", s.withAuth(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"version": Version})
	}))
	mux.HandleFunc("/v1/status", s.withAuth(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, s.statusSnapshot())
	}))
	mux.HandleFunc("/v1/start", s.withAuth(func(w http.ResponseWriter, r *http.Request) {
		var req startRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		status, err := s.startMihomo(req)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, status)
	}))
	mux.HandleFunc("/v1/stop", s.withAuth(func(w http.ResponseWriter, _ *http.Request) {
		status, err := s.stopMihomo()
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, status)
	}))
	mux.HandleFunc("/v1/logs", s.withAuth(func(w http.ResponseWriter, r *http.Request) {
		lines, _ := strconv.Atoi(r.URL.Query().Get("lines"))
		if lines <= 0 {
			lines = 200
		}
		writeJSON(w, http.StatusOK, s.readLogs(lines))
	}))
	return mux
}

func (s *ServiceRuntime) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-YueLink-Token") != s.cfg.Token {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next(w, r)
	}
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}
