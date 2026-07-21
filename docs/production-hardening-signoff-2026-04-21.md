# Production Hardening Sign-Off Report — 2026-04-21

## Preconditions
- Latest readiness report file: `/tmp/production_readiness_20260421_140037.log`
- `bash scripts/verify_production_readiness.sh 5`: `Pass`
- Baseline brand restored to `svid`: `Pass`
- `git status` reviewed for unrelated dirty files: `Pass`
  - Outside this lane: `.github/workflows/release.yml`, `docs/qa_checklist.md`, `scripts/preflight_yubikey.sh`, `scripts/sign_windows_artifacts.sh`, and Windows signing docs/scripts

## Startup Evidence
- `svid`: `first_frame_presented 495ms`, `backend_startup_ready 901ms`, `media_kit_prewarm_ready 984ms`
- `vidcombo`: `first_frame_presented 426ms`, `backend_startup_ready 1022ms`, `media_kit_prewarm_ready 800ms`

## Svid
| # | Scenario | Status | Notes |
| --- | --- | --- | --- |
| 1 | Open a local video, then play, pause, and seek | Not enough evidence | Agent cannot truthfully claim GUI playback interaction without manual execution |
| 2 | Close fullscreen player, reopen same media | Not enough evidence | Resume persistence logic is covered, but fullscreen reopen prompt was not manually exercised |
| 3 | Fullscreen -> mini -> fullscreen | Pass | Runtime smoke covers compact lifecycle reattach and compact progress persistence |
| 4 | Fullscreen -> PiP/system PiP -> `Back to App` / `Open Player` / `Close` | Not enough evidence | Window transition services are tested, but OS-level PiP paths were not manually driven end-to-end |
| 5 | Subtitle search: change language, search, close quickly | Pass | `subtitle_search_sheet_test.dart` covers async close / `setState-after-dispose` regression |
| 6 | External subtitle scan on first open | Pass | Subtitle scan now runs off the UI thread; scan/coordinator/runtime smoke tests cover stale result discard and scan behavior |
| 7 | Start trim or conversion, then cancel mid-run | Pass | FFmpeg trim and conversion cancellation regressions pass in runtime smoke |

## VidCombo
| # | Scenario | Status | Notes |
| --- | --- | --- | --- |
| 1 | Launch cold app start | Pass | Readiness report shows clean cold start and baseline restored without brand drift |
| 2 | Queue 2-3 downloads | Pass | Runtime smoke covers queued dispatch in parallel without duplicate starts |
| 3 | Retry one failed job | Pass | `downloads_notifier_retry_test.dart` covers retry routing and queue continuation |
| 4 | `Pause all`, `Resume all`, `Cancel` on queued and active jobs | Pass | Pause/resume plus queued and active cancel routing are now covered by runtime smoke and repository/notifier regression tests |
| 5 | Compact queue `previous/next` and natural auto-advance | Pass | Queue continuity and rollback semantics are covered in runtime smoke and queue service tests |
| 6 | Fullscreen -> mini/PiP -> reopen current media | Not enough evidence | Compact progress persistence is covered automatically, but reopen flow was not manually exercised in the GUI |

## Summary
- Automated `Pass`: `9`
- `Fail`: `0`
- `Not enough evidence`: `4`

## Verdict
- Automated sign-off status: `Pass`
- Branch sign-off status: `Not enough evidence`

Reason:
- No automated regressions remain in the current lane.
- Remaining uncertainty is limited to GUI/manual runtime flows that this session could not execute honestly end-to-end.

## Final Manual Gate
To upgrade this branch from `Not enough evidence` to `Pass`, execute and record these remaining scenarios in [production-hardening-signoff.md](production-hardening-signoff.md):
- `Svid` local playback `play / pause / seek`
- `Svid` fullscreen close -> reopen same media
- `Svid` system PiP `Back to App / Open Player / Close`
- `VidCombo` fullscreen -> mini/PiP -> reopen current media
