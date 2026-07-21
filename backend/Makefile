.PHONY: run build test test-webhook lint docker-up docker-down docker-reset tidy admin-build admin-dev docker-image

# Build metadata injected via -ldflags. Read from git on each build so the
# binary always reports the commit it was built from. Override via env if
# building outside a git checkout (e.g. CI image stage).
VERSION   ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
GIT_SHA   ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LDFLAGS := -X github.com/snakeloader/backend/internal/buildinfo.Version=$(VERSION) \
           -X github.com/snakeloader/backend/internal/buildinfo.GitSHA=$(GIT_SHA) \
           -X github.com/snakeloader/backend/internal/buildinfo.BuildTime=$(BUILD_TIME)

run:
	go run -ldflags "$(LDFLAGS)" ./cmd/api

build: admin-build
	go build -ldflags "$(LDFLAGS)" -o bin/api ./cmd/api

# Backend-only build (skip admin SPA rebuild) — used by webhook deploy when
# only Go code changed.
build-backend-only:
	go build -ldflags "$(LDFLAGS)" -o bin/api ./cmd/api

admin-build:
	cd web/admin && npm install && npm run build

admin-dev:
	cd web/admin && npm run dev

test:
	go test ./... -v -count=1

# Integration tests requiring a live Postgres instance.
# Spins up postgres-test on TEST_DB_PORT (default 5433; override if a host
# Postgres already holds the port), runs tests with the `integration` build
# tag, tears the container down on exit. `--wait` blocks until the explicit
# pg_isready healthcheck in docker-compose.test.yml passes.
#
#   make test-webhook                       # 5433 (default)
#   TEST_DB_PORT=5434 make test-webhook     # custom port
test-webhook:
	@TEST_DB_PORT=$${TEST_DB_PORT:-5433}; \
	  trap 'TEST_DB_PORT=$$TEST_DB_PORT docker compose -f docker-compose.test.yml down -v >/dev/null 2>&1' EXIT; \
	  TEST_DB_PORT=$$TEST_DB_PORT docker compose -f docker-compose.test.yml up -d --wait postgres-test && \
	  DB_HOST=localhost DB_PORT=$$TEST_DB_PORT DB_USER=snakeloader DB_PASSWORD=test DB_NAME=snakeloader_test DB_SSL_MODE=disable \
	    GIN_MODE=test \
	    go test ./internal/premium/handler/... -count=1 -race -tags=integration -v

lint:
	golangci-lint run ./...

# Build the production backend Docker image with VERSION / GIT_SHA /
# BUILD_TIME injected. Use this — NOT bare `docker build` — so /health
# and /version report a real build identity. The wrapper computes the
# args from the local git checkout. Production deploy webhooks must
# call this target (or the underlying script directly), otherwise the
# image ships with `version=dev, git_sha=unknown`.
#
#   make docker-image                # tag = snakeloader-backend:latest
#   IMAGE_TAG=foo:v1 make docker-image
docker-image:
	bash ../scripts/build_backend_image.sh $(IMAGE_TAG)

docker-up:
	docker compose up -d

docker-down:
	docker compose down

docker-reset:
	docker compose down -v && docker compose up -d

tidy:
	go mod tidy
