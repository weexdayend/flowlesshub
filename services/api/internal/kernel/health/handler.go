package health

import (
	"context"
	"encoding/json"
	"net/http"
	"sync/atomic"
	"time"
)

type pinger interface {
	Ping(context.Context) error
}

type response struct {
	Status string `json:"status"`
}

// ReadinessGate combines dependency health with the process drain state.
type ReadinessGate struct {
	database pinger
	draining atomic.Bool
}

// NewReadinessGate constructs a readiness handler for the API process.
func NewReadinessGate(database pinger) *ReadinessGate {
	return &ReadinessGate{database: database}
}

// MarkDraining removes the process from readiness before graceful shutdown.
func (g *ReadinessGate) MarkDraining() {
	g.draining.Store(true)
}

// ServeHTTP reports whether the API may receive new traffic.
func (g *ReadinessGate) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if g.draining.Load() {
		writeJSON(w, http.StatusServiceUnavailable, response{Status: "draining"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := g.database.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, response{Status: "unavailable"})
		return
	}

	writeJSON(w, http.StatusOK, response{Status: "ok"})
}

// Liveness reports that the API process can accept requests.
func Liveness(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, response{Status: "ok"})
}

func writeJSON(w http.ResponseWriter, status int, payload response) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
