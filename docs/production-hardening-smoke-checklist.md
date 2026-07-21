# Production Hardening Smoke Checklist

Use this gate after hardening/perf commits and before merging to `main`.

## 1. Cold-Start Baseline
- Run `bash scripts/profile_startup_macos.sh ssvid`
- Run `bash scripts/profile_startup_macos.sh vidcombo`
- Record `first_frame_presented`, `media_kit_prewarm_ready`, and `backend_startup_ready`

Current baseline on `2026-04-21`:
- `ssvid`: `first_frame_presented 425ms`, `media_kit_prewarm_ready 842ms`, `backend_startup_ready 636ms`
- `vidcombo`: `first_frame_presented 412ms`, `media_kit_prewarm_ready 763ms`, `backend_startup_ready 982ms`

Post-frame note:
- `desktop_integrations_ready` and `notification_permission_ready` now land after first frame by design; they should not be treated as startup blockers unless they visibly regress user interaction after launch
- `vidcombo` `backend_startup_ready` includes live premium/backend refresh work and can swing with network RTT; compare repeated runs before treating a single spike as a code regression
- Run startup profiles serially; the script now enforces a lock because concurrent runs share macOS brand/build artifacts and can produce false failures

Regression rule:
- Treat `first_frame_presented > 700ms` as a red flag
- Treat `backend_startup_ready` regressions over `+1000ms` as investigation-required

## 2. Playback + Subtitle Smoke
- Fast path: run `bash scripts/run_runtime_smoke_tests.sh` for subtitle search/dispose, subtitle download/save, stale scan discard, stale resume pruning, compact-player lifecycle reattach, compact PiP progress persistence, watch-progress lifecycle policy, and FFmpeg cancel regressions
- Open a local video and verify play, pause, seek, and window close produce no crash
- Play part of a file, close the player, reopen it, and confirm the resume prompt appears only for meaningful progress
- Close the app or player surface directly from fullscreen or compact mode, reopen the same media, and confirm the latest meaningful resume point persists
- Enter PiP or mini player, leave playback running there for a few seconds, reopen the fullscreen player, and confirm progress saving / playback completion still behave normally after the transfer
- With system PiP enabled, blur the app into system PiP, then use `Back to App`, `Open Player`, and `Close`; expect the latest resume point to persist across each path
- In compact mode, use `previous/next` queue controls and let a track end naturally; confirm queue continuity stays in compact mode unless the next item changes media surface
- Open subtitle search, change language, search, and close the sheet quickly; expect no red screen or `setState()` after dispose
- Load a video with external subtitles and confirm initial subtitle scan does not freeze the UI
- Start trim or conversion, cancel while FFmpeg is running, and confirm final status is `cancelled`, not `failed`

## 3. Download Queue Smoke
- Fast path: `bash scripts/run_runtime_smoke_tests.sh` covers queue dispatch, pause/resume/cancel lifecycle actions, and progress-write regressions
- Queue 2-3 downloads and verify queued jobs start without duplicate dispatch
- Retry one failed job and confirm the queue continues using available slots
- Run `Pause all`, `Resume all`, and `Cancel` on both queued and active jobs
- Confirm progress totals remain stable and UI updates stay smooth

## 4. Merge Gate
- `fvm flutter analyze --no-pub`
- `fvm flutter test`
- macOS debug smoke build for both brands must pass
