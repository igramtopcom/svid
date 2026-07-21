FROM golang:1.24-alpine AS builder

# Build-time identity for /health + /version. Empty defaults so the
# buildinfo.init() fallback path (runtime/debug.ReadBuildInfo VCS scan +
# "dev" / "unknown" terminal fallback) takes over when the deploy pipeline
# forgets to pass these. Production was reporting `version=dev,
# git_sha=unknown` because previous Dockerfile compiled with bare
# `-ldflags="-w -s"` and Go's VCS auto-stamping doesn't help once the
# binary leaves the build container without VCS metadata embedded.
#
# Recommended invocation in the deploy webhook:
#   docker build \
#     --build-arg VERSION=$(git describe --tags --always --dirty) \
#     --build-arg GIT_SHA=$(git rev-parse HEAD) \
#     --build-arg BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#     -t snakeloader-backend .
ARG VERSION=
ARG GIT_SHA=
ARG BUILD_TIME=

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s \
      -X github.com/snakeloader/backend/internal/buildinfo.Version=${VERSION} \
      -X github.com/snakeloader/backend/internal/buildinfo.GitSHA=${GIT_SHA} \
      -X github.com/snakeloader/backend/internal/buildinfo.BuildTime=${BUILD_TIME}" \
    -o /api cmd/api/main.go

FROM alpine:3.19

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app
COPY --from=builder /api .

EXPOSE 8080

CMD ["./api"]
