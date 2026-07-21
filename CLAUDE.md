# CLAUDE.md — Svid Desktop App

## Role

You are a Senior Engineer & Technical Advisor for Svid — a cross-platform desktop video downloader.
- **Primary**: Builder / Workflow Owner for bounded tasks. Audit → Plan → Implement → Verify, but only inside the task packet and stop conditions.
- **Secondary**: Proactively flag issues as `[TECH INSIGHT]` when they materially affect the current task.
- Do not make release, billing, credential, remote, force-update, rollback, or product-direction decisions independently.
- Treat Codex review as adversarial input, not authority. Respond with `accept`, `reject with evidence`, `defer`, or `minimal fix`; do not blindly expand scope because Codex does not sign off.

## Operating Contract

- Read `docs/ops/AI_OPERATING_CONTRACT.md` before substantial work.
- Start bounded work from `docs/ops/TASK_PACKET_TEMPLATE.md`.
- Use `docs/ops/REVIEW_VERDICT_PROTOCOL.md` when receiving or producing review verdicts.
- Telemetry/workflows produce leads. Root cause needs raw evidence + code path + repro or instrumentation.
- If the user is frustrated, slow down, restate the gate, and verify the current state. Do not rush into broader edits to appease emotion.
- No continuous loop. Every loop needs a max pass count, stop condition, and proof artifact.

## Project

- **App**: Svid v1.0.0 — download videos from 1000+ platforms (YouTube, TikTok, Instagram, X, etc.)
- **Status**: Production-released. CI/CD pipeline green on macOS, Windows, Linux.
- **Landing page**: https://svid.app/

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | Flutter 3.29.3 (via FVM) + Dart 3.7.2 |
| Native engine | Rust (flutter_rust_bridge FFI) — yt-dlp process management, download engine |
| Database | Drift (SQLite) with watch streams |
| State management | Riverpod (code-generated) |
| Backend | Go 1.21+ / Gin / GORM / PostgreSQL 16 / Redis 7 |
| Admin dashboard | React 18 + TypeScript + Vite (embedded in Go binary via `go:embed`) |
| CI/CD | GitHub Actions — builds macOS (.dmg), Windows (.exe/.zip), Linux (.AppImage) |

## Multi-Brand Architecture

Single repo, compile-time brand selection via `--dart-define=BRAND=svid|vidcombo`.

| Brand | Bundle ID | Backend | Payment | Theme |
|-------|-----------|---------|---------|-------|
| Svid | com.svid.app | Go (X-API-Key) | In-app Stripe + Crypto | Wine Red "Nocturne Cinematic" |
| VidCombo | com.tinasoft.vidcombo | PHP (checkkey.php) | Website + Manual Key | Arctic Blue "Arctic Command" |

**Key files:**
- `lib/core/config/brand_config.dart` — BrandConfig singleton (all brand-specific values)
- `scripts/set_brand.sh` — Platform config switcher (run BEFORE `flutter build`)
- `macos/Runner/Configs/brands/` — Per-brand xcconfig files
- `windows/runner/brand_config.h` — Generated C header for Windows native
- `assets/brands/{svid,vidcombo}/` — Per-brand logos, icons, tray icons

**Build commands:**
```bash
scripts/set_brand.sh vidcombo                              # Switch platform configs
fvm flutter build macos --dart-define=BRAND=vidcombo        # Build VidCombo macOS
```

**Adding a new brand:** New `Brand` enum value + `BrandConfig` subclass + xcconfig + `assets/brands/` directory + `set_brand.sh` case. Zero Dart code changes needed — all filenames, Sentry tags, exports derive from `BrandConfig.current`.

## Git Workflow

```
Remotes:
  kynndev → https://github.com/kynndev/svid_app.git  ← production target when authenticated and approved
  origin  → may be a non-production local default; verify with `git remote -v`

Production branch: kynndev/main after explicit confirmation
```

**Rules**:
- Never assume `origin` is production.
- Always state remote + branch before any push/pull/merge/release operation.
- Never force-push to main
- Backend production runs from the approved production remote/branch via deploy webhook. Verify deployed SHA via `curl https://api.svid.app/health` after pushing — if `git_sha` lags, the webhook may need a manual trigger.

> Historical note: local remotes have changed across sessions. Treat this section as a guardrail, not permission to push. Current remotes must be checked in-session.

## Directory Structure

```
snakeloader/                      ← ROOT
├── lib/                          ← Flutter app (Dart)
│   ├── core/                     ← Shared: auth, binaries, database, network, theme, utils
│   │   ├── binaries/             ← Binary download/management (yt-dlp, ffmpeg, gallery-dl)
│   │   ├── database/             ← Drift SQLite schema + DAOs
│   │   └── services/             ← Proxy rotation, circuit breaker, notifications
│   └── features/                 ← 11 feature modules (Clean Architecture)
│       ├── downloads/            ← Core download management (98 files)
│       ├── browser/              ← In-app WebView (36 files)
│       ├── player/               ← Media playback + PiP (31 files)
│       ├── premium/              ← Payment + licensing (22 files)
│       ├── settings/             ← User preferences (17 files)
│       ├── youtube_search/       ← YouTube search (15 files)
│       ├── youtube_channel/      ← Channel downloads (21 files)
│       ├── youtube_playlist/     ← Playlist handling (10 files)
│       ├── support/              ← Tickets + feature requests (14 files)
│       ├── home/                 ← Dashboard + URL entry (13 files)
│       └── assistant/            ← AI chat (9 files)
├── test/                         ← 141 test files
├── native/                       ← Rust FFI code (16 .rs files)
├── macos/                        ← macOS runner + native.framework
├── windows/                      ← Windows runner + native.dll
├── linux/                        ← Linux runner + libnative.so
├── backend/                      ← Go backend (in-repo, separate deployment)
│   ├── cmd/api/main.go
│   ├── internal/                 ← 7 modules: identity, bugs, product, feedback, assistant, analytics
│   ├── web/admin/                ← React admin dashboard
│   └── docker-compose.yml
├── website/                      ← Landing page (svid.app) + version.json
├── scripts/                      ← Build/package/install scripts
├── memory/                       ← Phase tracking (gitignored, local only)
├── docs/                         ← QA checklist, accessibility audit
├── assets/                       ← Translations (en/vi), icons
└── .github/workflows/release.yml ← CI/CD pipeline
```

## Build Commands

### Frontend (Flutter + Rust)

```bash
# Development — preferred (handles brand + Rust + flutter run in one shot)
scripts/dev.sh                     # svid debug
scripts/dev.sh vidcombo            # vidcombo debug
scripts/dev.sh svid release       # svid release build + native.framework verify
scripts/dev.sh vidcombo release    # vidcombo release build + verify

# Manual (only if dev.sh fails)
fvm flutter pub get
dart run build_runner build --delete-conflicting-outputs
scripts/set_brand.sh svid         # or vidcombo — switches xcconfig + icons
CONFIGURATION=Debug bash macos/build_rust.sh
fvm flutter run -d macos --dart-define=BRAND=svid

# Production build (macOS) — manual
cd native && cargo build --release --target aarch64-apple-darwin && cd ..
CONFIGURATION=Release bash macos/build_rust.sh
fvm flutter build macos --release --dart-define=BRAND=svid
bash scripts/package_macos.sh svid    # → dist/Svid-X.Y.Z-macos-universal.dmg

# Verify build
codesign --verify --deep --strict build/macos/Build/Products/Release/svid.app

# Analysis & tests
fvm flutter analyze --no-pub
fvm flutter test
```

### Backend (Go)

```bash
cd backend
docker compose up -d              # PostgreSQL + Redis
make run                          # Dev server (port 8080)
make build                        # Production binary (includes admin dashboard)
make admin-dev                    # Admin dashboard dev (Vite port 3000)
```

### CI/CD

Pipeline triggers on `git tag v*` push or manual `workflow_dispatch`.
Builds all 3 platforms in parallel → creates GitHub Release with artifacts.

## Architecture

### Clean Architecture (per feature module)

```
feature/
├── data/
│   ├── datasources/       ← External data (API, subprocess, file I/O)
│   ├── repositories/      ← Implements domain interfaces
│   └── models/            ← DTOs, JSON serialization
├── domain/
│   ├── entities/          ← Business objects (freezed)
│   ├── repositories/      ← Abstract interfaces
│   ├── usecases/          ← Business logic
│   └── services/          ← Domain services
└── presentation/
    ├── screens/           ← Full pages
    ├── widgets/           ← UI components
    └── providers/         ← Riverpod state management
```

### Binary Management (critical path)

App downloads 4 binaries on first launch:
- **yt-dlp**: Video extraction + download (zipapp on macOS with Python 3.10+, exe on Windows)
- **ffmpeg + ffprobe**: Post-processing, format conversion, metadata
- **gallery-dl**: Image/carousel downloads (Instagram, etc.)
- **Deno**: External JavaScript runtime — REQUIRED by yt-dlp 2025.11.12+ to solve YouTube nsig + n-challenge. Without it, YouTube extraction returns storyboards-only and stderr logs `[jsc:deno] Solving JS challenges using deno` is absent. Path is threaded explicitly into every yt-dlp invocation via `--js-runtimes deno:<path>` (do NOT rely on PATH inheritance — sandboxed builds drop env vars). Threaded through Rust FFI param `js_runtime_path` for `ytdlp_extract_info` / `ytdlp_search_youtube` / `ytdlp_get_playlist_info` / `ytdlp_get_channel_info` / `ytdlp_get_channel_metadata`.

Architecture-aware downloads:
- macOS: `BinaryManager.macOSArch` → `arm64` or `amd64` (martin-riedl.de for ffmpeg, denoland/deno releases for Deno)
- Windows: x86_64 only
- Linux: x86_64 only

### Backend ↔ Frontend Integration

- API base: `https://api.svid.app/api/v1/`
- Auth: `X-API-Key` header (format: `snk_` + base64url)
- Response: `{ success, data, error: { code, message, details } }`
- Error codes: `UPPER_SNAKE_CASE`
- All IDs: UUID v4

## Coding Conventions

- **Dart**: Follow `flutter_lints`, prefer `const`, use `freezed` for entities
- **Riverpod**: Code-generated providers (`@riverpod` annotation)
- **Imports**: Relative within feature, package imports across features
- **Error handling**: `Result<T>` pattern (Success/Failure), never throw in use cases
- **Naming**: camelCase (Dart), snake_case (Rust), UPPER_SNAKE_CASE (error codes)
- **Generated files**: `*.g.dart`, `*.freezed.dart` — gitignored, regenerate with `build_runner`
- **FRB bindings**: Committed for CI stability. Regenerate: `flutter_rust_bridge_codegen generate`
- **No over-engineering**: Fix what's asked, don't add extras. 3 similar lines > premature abstraction.

## Critical Gotchas

### macOS Production Build
- **MUST use `fvm flutter`** — never bare `flutter`
- **yt-dlp PyInstaller delay**: `yt-dlp_macos` = PyInstaller → XProtect scan 6-45s. FIX: Download zipapp `yt-dlp`, patch shebang to Python 3.10+
- **native.framework signing**: Sign the BINARY (`Versions/A/native`), NOT the bundle. Bundle signing creates rogue symlinks.
- **Rust FFI release**: `flutter_rust_bridge` default loader fails in release. Fix in `main.dart` uses `Platform.resolvedExecutable` to find framework.
- **Content hash mismatch**: After ANY Rust change: codegen → cargo build → copy dylib → flutter clean → build

### Binary Architecture
- **ffmpeg/ffprobe**: martin-riedl.de (arm64 + amd64). evermeet.cx is x86_64 only — crashes on Apple Silicon.
- **gallery-dl_macos**: ARM64 only (gdl-org/builds). Intel Macs need Rosetta 2.
- **yt-dlp_macos**: Universal binary — no architecture issue.

### Rust FFI
- `ytdlp_datasource.dart` calls `native.ytdlpExtractInfo()` — requires Rust bridge, not Dart subprocess
- `native/target/aarch64-apple-darwin/release/libnative.dylib` must match `macos/native.framework/Versions/A/native`
- Release mode: only warning+ log level (`_AppLogFilter`)

### Hot Restart
- **Hot restart is BROKEN for `media_kit`** — native plugin loading is one-shot per process. Symptom: `MediaKit.ensureInitialized` error after `r` in flutter run, video player stops working.
- Workaround: full quit (`q`) + re-run. Hot **reload** (`R` lowercase) works fine for non-native code.
- This is a Flutter platform-channel limitation, not a project bug. See media-kit/media-kit#installation.

### General
- Bash: `!`/`@` in JSON bodies — use single quotes or `--data-raw`
- `http.FileServer` causes SPA redirect issues — use `http.ServeContent`
- Version comparison: semver part-by-part, NOT `published_at` ordering

### Installer / Native / Release Hardening (2026-04 session)
- **Release-gate before push**: `scripts/verify_release_gates.sh` aggregates every Installer/Native gate (analyze, locked tests, Windows signing policy, Rust cargo check, brand assets, Inno Setup Docker compile × brands). Must run green before any release tag. `--fast` skips the Inno compile for pre-commit loops.
- **Windows signing policy** (`scripts/windows_signing_common.sh` → `enforce_windows_signing_policy`): rejects ECC/ECDSA certs (Smart App Control blocks them on Win11), requires RSA ≥ 3072 bits, FAILs on certs within 14 days of expiry. Preferred slot is 9C per `docs/windows-signing-policy.md`. Override `SKIP_WINDOWS_SIGNING_POLICY=1` only for diagnostic builds — CI must never set it.
- **Installer [Run] section MUST have dual entries**: `postinstall skipifsilent` for interactive + `skipifnotsilent` for `/VERYSILENT` auto-update. Single `postinstall` alone does NOT relaunch in silent mode — installer closes the app via Restart Manager and never reopens it. This regression silently breaks the entire auto-update UX.
- **Auto-update download**: streaming SHA-256 via `sha256.bind(file.openRead()).first` (no whole-file RAM allocation), `Range: bytes=N-` resume on partial files, case-insensitive hex compare. The `http.Client` is `SharedHttpClient.instance` — `close()` on the shared singleton is a no-op so any consumer's dispose() is safe.
- **Binary supply-chain**: yt-dlp downloads verify against upstream `SHA2-256SUMS` manifest before accepting the binary. `BinaryDownloader.parseChecksums` is `@visibleForTesting`; don't widen what counts as a valid hex digest without updating the 12 unit tests that lock the parser behavior.
- **Bound every network send**: every `_client.send(...)` / `_client.get(...)` must carry `.timeout(Duration)`. A stalled CDN otherwise hangs binary provisioning or auto-update indefinitely before the OS-level TCP timeout fires minutes later.
- **Keychain probe, not retry loop**: `SecureCredentialStore` probes the platform secure storage once, caches availability for 24h in SharedPreferences, and falls back to plaintext prefs when unavailable (unsigned debug builds, broken DPAPI). Per-key retry spam on every launch was the old bug.
- **Native platform channels via FlutterPlugin registrar** (`MainFlutterWindow.swift`), not `engine.binaryMessenger` direct wiring. Registrar pattern survives hot restart; direct wiring leaves a stale handler → every `requestPermission` / `shareFile` throws MissingPluginException.
- **VidCombo installer marker** (`%TEMP%\vidcombo_installer_ran.txt`): idempotent via mtime fingerprint stored in SharedPreferences. After 3 consecutive delete failures the code force-accepts AND fingerprints — without that fingerprint a permanently-locked marker would wipe the premium license on every launch forever (the anti-loop anti-loop).
- **VidCombo checkkey cache**: 15-minute TTL premium response cache via `StartupService.writeVidComboCheckKeyCache` / `readVidComboCheckKeyCache`. Skip PHP round-trip on boots within TTL; background-refresh on hit; non-premium responses are deliberately NOT cached (just-purchased user must see premium on next launch).
- **Rust download manager**: terminal tasks (Completed/Failed/Cancelled) are stamped with `terminal_at` and swept out of the HashMap after `TERMINAL_TTL` (10 min) by `sweep_expired_tasks`, called lazily from any op that already holds the tasks lock. Keeps memory bounded when the Dart side forgets to call `cleanup_download`. Cancelled state beats a late Completed — user cancel wins the race.

## Design System

- **`DESIGN.md`**: Design tokens (colors, typography, spacing, component patterns). Read before ANY UI work.
- **`STITCH.md`**: Registry of all Google Stitch design projects + screens. Read before generating/reviewing designs.
- Direction: **Nocturne Cinematic** — dark-first, wine red (#8D021F) + crimson (#C41E3A), Inter font, tonal layering.
- Always generate Dark + Light variants. Use Stitch prompt template from DESIGN.md for consistency.
