package buildinfo

import "runtime/debug"

// Build-time identity. Three sources, in priority order, populated by init()
// functions across this package:
//
//  1. -ldflags injection (this file's vars). Wins when present, e.g. when
//     `make build` or scripts/build_backend_image.sh runs.
//  2. runtime/debug.ReadBuildInfo() VCS auto-embed (Go 1.18+). Works when
//     building from a git checkout with package-form invocation (./cmd/api).
//  3. Embedded constants in embedded.go, regenerated and committed via
//     scripts/regenerate_buildinfo.sh before each release push. This is the
//     last-resort source for the production deploy path, where the docker
//     build context is `backend/` (no .git available) and the webhook
//     doesn't pass build-args. Without this, /version reports `dev`/`unknown`
//     forever no matter what the deploy script does.
//  4. Terminal "dev"/"unknown" fallback in zfallback.go — runs last, fills
//     in literal placeholders so /version is never empty.
//
// Init order is alphabetical by filename: buildinfo.go → embedded.go →
// zfallback.go. Each file checks `if X == ""` before writing, so an earlier
// source wins over a later one.
//
// Example -ldflags invocation (preferred — clean tag-based Version):
//
//	go build -ldflags "-X github.com/snakeloader/backend/internal/buildinfo.Version=v1.6.2 \
//	                   -X github.com/snakeloader/backend/internal/buildinfo.GitSHA=abc123 \
//	                   -X github.com/snakeloader/backend/internal/buildinfo.BuildTime=2026-04-25T12:00:00Z"
var (
	Version   = ""
	GitSHA    = ""
	BuildTime = ""
)

func init() {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return
	}
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			if GitSHA == "" {
				GitSHA = s.Value
			}
		case "vcs.time":
			if BuildTime == "" {
				BuildTime = s.Value
			}
		case "vcs.modified":
			if s.Value == "true" && GitSHA != "" {
				GitSHA += "-dirty"
			}
		}
	}
	if Version == "" && info.Main.Version != "" && info.Main.Version != "(devel)" {
		Version = info.Main.Version
	}
}
