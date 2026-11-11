package main

import (
	"context"
	"fmt"

	"github.com/riverqueue/river"
)

// bootstrapNoopJobKind is a reserved platform handler used only to let the
// River worker process start before business modules register their own jobs.
const bootstrapNoopJobKind = "flowlesshub_platform_bootstrap_noop"

type bootstrapNoopArgs struct{}

func (bootstrapNoopArgs) Kind() string { return bootstrapNoopJobKind }

type bootstrapNoopWorker struct {
	river.WorkerDefaults[bootstrapNoopArgs]
}

// Work intentionally has no side effects. It only returns context cancellation
// so River can stop the handler cleanly during worker shutdown.
func (*bootstrapNoopWorker) Work(ctx context.Context, _ *river.Job[bootstrapNoopArgs]) error {
	return ctx.Err()
}

func newWorkers() (*river.Workers, error) {
	workers := river.NewWorkers()
	if err := river.AddWorkerSafely[bootstrapNoopArgs](workers, &bootstrapNoopWorker{}); err != nil {
		return nil, fmt.Errorf("register platform bootstrap worker: %w", err)
	}

	return workers, nil
}
