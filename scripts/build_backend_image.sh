#!/usr/bin/env bash
# =============================================================================
# Backend Docker image build wrapper.
#
# Why this exists: backend/Dockerfile accepts VERSION / GIT_SHA / BUILD_TIME
# as ARGs that ldflags-inject into `internal/buildinfo`. If `docker build` is
# called without those build-args, the binary ships with the buildinfo init()
# fallbacks (`Version="dev", GitSHA="unknown"`), which is the regression that
# kept production /health reporting `version: dev, git_sha: unknown` for the
# v1.3.6 / v1.6.3 cycle.
#
# This script computes the args from the local git checkout and invokes
# `docker build` with them. Any deploy path that builds the backend image
# (production webhook on kynndev, manual SSH session, CI job, …) should
# call THIS script instead of bare `docker build` so the resulting binary
# is always traceable to a commit.
#
# Usage:
#
#   bash scripts/build_backend_image.sh [TAG]
#     TAG defaults to `snakeloader-backend:latest` if omitted.
#
#   IMAGE_TAG=foo bash scripts/build_backend_image.sh
#     Same as positional, env override.
#
# After deploy, verify by hitting the running container's /health and
# confirming that `version` is a real semver/git-describe string and
# `git_sha` is a real 40-char SHA, not the literal strings `dev` /
# `unknown`. preflight_release.sh Gate 3 also depends on records being
# registered with proper versions, so this fix and that fix compose.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"

if [ ! -f "$BACKEND_DIR/Dockerfile" ]; then
  echo "ERROR: $BACKEND_DIR/Dockerfile not found" >&2
  exit 1
fi

TAG="${1:-${IMAGE_TAG:-snakeloader-backend:latest}}"

# Compute build identity from git. Match the targets the Makefile uses
# locally, so `make build` and `docker build` produce binaries whose
# /health output is comparable.
VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)"
GIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Building backend image"
echo "  tag        = $TAG"
echo "  version    = $VERSION"
echo "  git_sha    = $GIT_SHA"
echo "  build_time = $BUILD_TIME"

docker build \
  --build-arg "VERSION=$VERSION" \
  --build-arg "GIT_SHA=$GIT_SHA" \
  --build-arg "BUILD_TIME=$BUILD_TIME" \
  -t "$TAG" \
  "$BACKEND_DIR"

echo "Build complete: $TAG"
echo
echo "Verify after running:"
echo "  docker run --rm $TAG /api -version 2>/dev/null || \\"
echo "    docker inspect --format '{{json .Config.Labels}}' $TAG"
echo "  curl -s http://<host>/health | jq '{version,git_sha}'"
