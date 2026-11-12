.PHONY: api-run worker-run api-test api-vet api-fmt migrate-run db-up db-down river-migrate-up river-migrate-down sqlc openapi-go openapi-ts arch-lint db-lint images-web images-backend k8s-build edge-validate

api-run:
	cd services/api && go run ./cmd/api

worker-run:
	cd services/api && go run ./cmd/worker

api-test:
	cd services/api && go test ./...

api-vet:
	cd services/api && go vet ./...

api-fmt:
	find services/api/cmd services/api/internal -type f -name '*.go' -print0 | xargs -0 gofmt -w

migrate-run:
	cd services/api && go run ./cmd/migrate

db-up:
	go run github.com/pressly/goose/v3/cmd/goose@v3.30.0 -dir services/api/db/migrations postgres "$(DATABASE_URL)" up

db-down:
	go run github.com/pressly/goose/v3/cmd/goose@v3.30.0 -dir services/api/db/migrations postgres "$(DATABASE_URL)" down

river-migrate-up:
	go run github.com/riverqueue/river/cmd/river@v0.51.2 migrate-up --database-url "$(DATABASE_URL)"

river-migrate-down:
	go run github.com/riverqueue/river/cmd/river@v0.51.2 migrate-down --database-url "$(DATABASE_URL)"

sqlc:
	cd services/api && go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate -f sqlc.yaml

openapi-go:
	cd services/api && mkdir -p internal/platform/httpapi && go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.8.1 --config oapi-codegen.yaml ../../api/openapi.yaml

openapi-ts:
	pnpm api:generate

arch-lint:
	cd services/api && go run github.com/fe3dback/go-arch-lint@v1.19.1 check --project-path .

db-lint:
	squawk --pg-version=17.0 --assume-in-transaction --include=require-timeout-settings "services/api/db/migrations/*.sql"

images-web:
	docker buildx build --load --file apps/web/Dockerfile --tag flowlesshub-web:dev .

images-backend:
	docker buildx build --load --build-arg APP=api --file services/api/Dockerfile --tag flowlesshub-api:dev .
	docker buildx build --load --build-arg APP=worker --file services/api/Dockerfile --tag flowlesshub-worker:dev .
	docker buildx build --load --build-arg APP=migrate --file services/api/Dockerfile --tag flowlesshub-migrate:dev .

edge-validate:
	bash scripts/k8s/validate-edge-config.sh
	bash scripts/k8s/validate-edge-manifests.sh

k8s-build:
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/base > /dev/null
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/migrations > /dev/null
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/overlays/local > /dev/null
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/overlays/green > /dev/null
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/overlays/production > /dev/null
	go run sigs.k8s.io/kustomize/kustomize/v5@v5.8.3 build deploy/k8s/overlays/production-green > /dev/null
