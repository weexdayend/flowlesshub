package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/weexdayend/flowlesshub/services/api/internal/kernel/config"
	"github.com/weexdayend/flowlesshub/services/api/internal/kernel/health"
	"github.com/weexdayend/flowlesshub/services/api/internal/platform/database"
)

const (
	readinessDrainDelay = 5 * time.Second
	serverShutdownLimit = 25 * time.Second
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		logger.Error("load configuration", "error", err)
		os.Exit(1)
	}

	startupCtx, cancelStartup := context.WithTimeout(context.Background(), 10*time.Second)
	pool, err := database.Open(startupCtx, cfg.DatabaseURL)
	cancelStartup()
	if err != nil {
		logger.Error("connect to PostgreSQL", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	readiness := health.NewReadinessGate(pool)

	router := chi.NewRouter()
	router.Use(middleware.RequestID)
	router.Use(middleware.RealIP)
	router.Use(middleware.Recoverer)
	router.Get("/livez", health.Liveness)
	router.Get("/readyz", readiness.ServeHTTP)

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("API server listening", "address", cfg.HTTPAddr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("API server stopped unexpectedly", "error", err)
			os.Exit(1)
		}
	case <-ctx.Done():
		readiness.MarkDraining()
		logger.Info("API entering drain mode", "readiness", "draining", "drain_delay", readinessDrainDelay)

		drainTimer := time.NewTimer(readinessDrainDelay)
		<-drainTimer.C

		shutdownCtx, cancel := context.WithTimeout(context.Background(), serverShutdownLimit)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			logger.Error("graceful shutdown failed", "error", err)
			_ = server.Close()
		}
		if err := <-serverErrors; err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("API server shutdown", "error", err)
		}
	}
}
