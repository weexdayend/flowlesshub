package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/riverqueue/river/riverdriver/riverpgxv5"
	"github.com/riverqueue/river/rivermigrate"

	"github.com/weexdayend/flowlesshub/services/api/db/migrations"
	"github.com/weexdayend/flowlesshub/services/api/internal/kernel/config"
	"github.com/weexdayend/flowlesshub/services/api/internal/platform/database"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	if err := run(ctx, logger); err != nil {
		logger.Error("database migration failed", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	pool, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	// Goose uses database/sql; OpenDBFromPool shares the already verified pgx
	// pool instead of creating a second independent set of connections.
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer sqlDB.Close()

	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	goose.SetBaseFS(migrations.FS)
	if err := goose.UpContext(ctx, sqlDB, "."); err != nil {
		return err
	}
	logger.Info("application SQL migrations are current")

	// River's migrator owns the river_migration history and its schema versioning.
	riverMigrator, err := rivermigrate.New(riverpgxv5.New(pool), nil)
	if err != nil {
		return err
	}
	result, err := riverMigrator.Migrate(ctx, rivermigrate.DirectionUp, nil)
	if err != nil {
		return err
	}

	migrated := 0
	if result != nil {
		migrated = len(result.Versions)
	}
	logger.Info("River schema is current", "new_migrations", migrated)
	return nil
}
