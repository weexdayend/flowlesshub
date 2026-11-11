package main

import (
	"context"
	"errors"
	"testing"

	"github.com/riverqueue/river"
)

func TestNewWorkersRegistersBootstrapNoopWorker(t *testing.T) {
	workers, err := newWorkers()
	if err != nil {
		t.Fatalf("newWorkers() error = %v", err)
	}

	if got, want := (bootstrapNoopArgs{}).Kind(), "flowlesshub_platform_bootstrap_noop"; got != want {
		t.Fatalf("bootstrap worker kind = %q, want %q", got, want)
	}

	err = river.AddWorkerSafely[bootstrapNoopArgs](workers, &bootstrapNoopWorker{})
	if err == nil {
		t.Fatal("expected duplicate bootstrap worker registration to be rejected")
	}
	if err.Error() != `worker for kind "flowlesshub_platform_bootstrap_noop" is already registered` {
		t.Fatalf("duplicate registration error = %q", err)
	}
}

func TestBootstrapNoopWorkerCompletesWithActiveContext(t *testing.T) {
	worker := &bootstrapNoopWorker{}
	if err := worker.Work(context.Background(), nil); err != nil {
		t.Fatalf("Work() error = %v, want nil", err)
	}
}

func TestBootstrapNoopWorkerHonorsContextCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	worker := &bootstrapNoopWorker{}
	err := worker.Work(ctx, nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("Work() error = %v, want %v", err, context.Canceled)
	}
}
