# SSvid QA Checklist

Pre-release quality gate — run before every release tag.

---

## Automated Gate (CI — runs on every `v*` tag push)

| Check | Command | Pass Criteria |
|-------|---------|---------------|
| Static analysis | `flutter analyze --no-fatal-infos` | Zero errors |
| Unit tests | `flutter test --coverage --reporter compact` | All pass (pre-existing skips documented below) |
| macOS build | `flutter build macos --release` | Artifact produced, size < 200 MB |
| Windows build | `flutter build windows --release` | Artifact produced |
| Linux build | `flutter build linux --release` | AppImage produced |

### Known permanent skips / pre-existing failures
- 10 tests: Supabase integration tests (require live credentials)

---

## Platform Matrix (Manual — once per release)

| Platform | Artifact | Tester |
|----------|----------|--------|
| macOS M1 (Apple Silicon) | Release DMG | Human |
| macOS Intel (x86_64) | Release DMG | Human |
| Windows 10 | Release ZIP | Human |
| Windows 11 | Release ZIP | Human |
| Windows 11 fresh install (`Smart App Control ON`) | Release EXE installer | Human |
| Windows 11 upgrade from previous stable | In-app update + Release EXE installer | Human |
| Ubuntu 22.04 LTS | AppImage | Human |

---

## Critical Path Scenarios (Manual — Human test)

### 1. Core download flow
- [ ] Paste YouTube/TikTok/Instagram URL → select format → download starts
- [ ] Download completes → file exists at save path → can open/play
- [ ] Download fails (invalid URL) → error shown, no crash

### 1A. Windows install and trust path
- [ ] On Windows 11 fresh install with `Smart App Control ON`, run the release installer `.exe` → installer is not blocked by Windows trust policy
- [ ] Installer completes → app launches from installer `[Run]` step
- [ ] Upgrade over previous stable Windows build preserves app data and launches normally
- [ ] In-app update from previous stable downloads, launches installer, and relaunches the new version

### 2. macOS native features
- [ ] Right-click completed download → "Share" → native share sheet opens (`NSSharingServicePicker`)
- [ ] Select URL in Safari/Chrome → Services menu → "Download with SSvid" → app opens + download queued
- [ ] `Cmd+Shift+D` while SSvid is backgrounded → app comes to front + new download dialog focused
- [ ] `Cmd+Option+V` while SSvid is backgrounded → clipboard URL starts downloading silently
- [ ] `Ctrl+Cmd+S` while SSvid is visible → window hides; repeat → window shows

### 3. Scheduled / recurring downloads
- [ ] Schedule a one-time download → fires at configured time
- [ ] Schedule a daily recurring download → `nextOccurrence()` advances after each fire

### 4. Priority queue
- [ ] Add 3 downloads with different priorities → high-priority runs first
- [ ] Drag-reorder queue → new order persists after app restart

### 5. Quiet hours
- [ ] Enable quiet hours 22:00–08:00 → active download throttled during window
- [ ] Outside quiet hours → full speed restored

### 6. Startup performance (macOS M1)
- [ ] Cold launch (no cached data) → first frame visible in < 2s
- [ ] Measure with Instruments / `flutter run --profile --trace-startup` if regression suspected

### 7. Error recovery
- [ ] Kill app mid-download → relaunch → download auto-resumes
- [ ] Offline → download fails gracefully → back online → auto-retry succeeds

### 8. File integrity
- [ ] Completed download → right-click → "Verify Integrity" → passes for valid file
- [ ] Corrupt file → integrity check shows failure

---

## Sentry Verification (Manual — once per release)

- [ ] Release tagged + deployed → Sentry dashboard shows new release `ssvid@<version>`
- [ ] Crash-free sessions rate visible in Sentry Release Health tab
- [ ] Download lifecycle breadcrumbs ("Download added", "Download completed", "Download failed") appear in Sentry event context

---

## Release Artifacts Checklist

- [ ] `SSvid-<version>-macos.dmg` — signed (codesign) + notarized (xcrun notarytool)
- [ ] `SSvid-<version>-windows-x64-setup.exe` — Authenticode-signed with RSA certificate + timestamped
- [ ] `SSvid-<version>-windows.zip` — bundled `ssvid.exe` and shipped DLLs signed
- [ ] `SSvid-<version>-linux.AppImage` — executable bit set
- [ ] `website/version.json` — updated with new version, download URLs, SHA-256 checksums
- [ ] GitHub Release created with auto-generated release notes
