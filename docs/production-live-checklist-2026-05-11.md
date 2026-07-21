# Production Live Checklist — Svid + VidCombo

Snapshot: 2026-05-11 08:56 UTC+7  
Source: Go backend admin API (`api.svid.app`) + legacy VidCombo feedback admin  
Scope: production users currently connected to Svid + VidCombo apps  
Raw local snapshot: `/tmp/svid_prod_snapshot_2026-05-11_raw`

Rule: this document is the current execution handoff. Do not use older memory, older audits, or historical docs as current production truth.

## Executive Verdict

Backend/API is healthy and production is live. Device adoption, VidCombo 1.6.5 adoption, premium license count, and revenue are all moving upward.

The app layer is still not clean. Compared with the 2026-05-06 snapshot, short-window crash volume improved, but download reliability worsened and open bugs increased. VidCombo 1.6.5 remains the main source of live app-side issues.

Do not report "all clear". Correct state: backend healthy, production usable, but app artifacts still have runtime/download reliability residue. The next codebase/release work should focus on download reliability, player/ref lifecycle residue, Windows asset packaging residue, WebView fallback, and runtime font/network degradation.

## Delta Since 2026-05-06

Positive:

- Devices increased from about 2,659 to 3,252.
- Active 7d increased from 1,233 to 1,443.
- VidCombo 1.6.5 total devices increased from 864 to 1,436.
- Premium licenses increased from 17 to 19.
- Month-to-date revenue increased from $105.79 to $175.69.
- Rolling 24h crash records decreased from 189 to 52.
- No rolling 24h critical crash records in this snapshot.

Negative:

- Open bugs increased from 10 to 14.
- Crash groups increased from 116 to 141.
- Download error total increased from 1,762 to 2,456.
- Dashboard download success rate dropped from 95% to 86%.
- VidCombo 1.6.5 remains dominant in crash and download-error telemetry.
- Download/extract errors are now the highest product-risk area, especially YouTube login/bot-check, unknown classification, and ffmpeg/post-process failures.

## Agent Execution Protocol

For every task below, agents must first classify the current codebase state:

- Already fixed but unreleased.
- Partially implemented.
- Missing implementation.
- Needs stack/log evidence before patching.

Do not reimplement existing gates or hardening from scratch. Patch only verified gaps, add targeted tests, and separate release-artifact verification from source-code implementation.

This document is valid for internal codebase execution. It is not a production release sign-off.

## Current Production Release State

Active production records:

- Svid 1.3.8 Windows: active, mandatory false, published 2026-04-28.
- Svid 1.3.8 macOS: active, mandatory false, published 2026-04-28.
- VidCombo 1.6.5 Windows: active, mandatory false, published 2026-04-28.
- VidCombo 1.6.5 macOS: active, mandatory false, published 2026-04-28.

Important:

- No production release record for Svid 1.3.9.
- No production release record for VidCombo 1.6.6.
- VidCombo 1.6.6 appears on 4 device records, but no matching release record exists. Treat as test/internal residue or release-registration gap until proven otherwise.
- `mandatory=false` means users can remain on old builds.

## Backend Health

Status: OK.

- `/health`: healthy.
- Database: connected.
- System health: OK.
- DB pool: open 2, idle 2.
- Memory: about 15 MB.
- Goroutines: 19.
- Backend uptime: about 117 hours.
- Backend version: `v1.6.1-85-gb37334fb-dirty`.
- Git SHA: `b37334fbb7a5e87546920f5f44d2b304a4d98233`.

Risk:

- Backend still reports `dirty` in build identity. This is not a user-facing outage, but it remains an operational traceability issue.

## Device / Adoption Snapshot

All brands:

- Total devices: 3,252.
- Active today: 35.
- Active 7d: 1,443.
- Rolling 24h active from device records: 346.
- New today: 7 by dashboard.
- Rolling 24h new from device records: 97.
- Windows: 2,697.
- macOS: 555.

Svid:

- Total devices: 576.
- Active today: 5.
- Active 7d: 183.
- Rolling 24h active: 48.
- Svid 1.3.8: 150 total, 105 active 7d, 28 active 24h.

VidCombo:

- Total devices: 2,676.
- Active today: 30.
- Active 7d: 1,259.
- Rolling 24h active: 298.
- VidCombo 1.6.5: 1,436 total, 1,061 active 7d, 248 active 24h.
- VidCombo 1.6.2: 986 total, 151 active 7d, 40 active 24h.
- VidCombo 1.6.1: 181 total, 31 active 7d, 8 active 24h.
- VidCombo 1.6.0: 41 total, 3 active 7d, 1 active 24h.
- VidCombo 1.6.6: 4 total, 3 active 7d, 1 active 24h.

OS telemetry caveat:

- Windows 11 is not reliably distinguished in current backend OS metadata. Most Windows devices report Windows 10-style strings.

## Priority Codebase Task Queue

### P0 — Download / Extract Reliability

Status: active and worsened since 2026-05-06.

Evidence:

- Dashboard download success rate: 86%.
- Rolling 24h raw download errors: 145.
- VidCombo rolling 24h download errors: 135.
- Svid rolling 24h download errors: 10.
- VidCombo 1.6.5 rolling 24h download errors: 121.
- Rolling 168h download errors: 1,059.
- Top rolling 24h codes: `loginRequired` 52, `unknown` 48, `networkTimeout` 11, `ffmpegError` 8, `diskFull` 6.
- Top rolling 24h platform: YouTube 129/145.

Required work:

- Fix/verify YouTube extraction failure handling and user messaging.
- Separate app circuit-breaker cooldown from actual YouTube/yt-dlp rate-limit.
- Ensure fallback client chain counts one logical extraction request, not each internal fallback attempt, if current code still increments per fallback client.
- Improve cookies/login-required UX.
- Improve classifier so `unknown` becomes actionable.
- Keep proxy/cookies behavior intact; do not remove existing mitigations.

Acceptance criteria:

- `loginRequired`, `rateLimited`, circuit-breaker-open, expired cookies, network timeout, and format unavailable each show distinct user-facing states.
- Backend structured download error `unknown` should drop materially after release.
- Add targeted tests for classifier and circuit-breaker logical request behavior.

### P0 — FFmpeg / Post-Process / Conversion Diagnostics

Status: active.

Evidence:

- Rolling 24h `ffmpegError`: 8.
- Rolling 72h `ffmpegError`: 30.
- Rolling 168h `ffmpegError`: 74.
- Common messages include `Postprocessing: Conversion failed`, interrupted conversion, output file missing, and HTTP 404 inside media streams.

Required work:

- Capture safe stderr tail, command phase, binary version, input/output metadata, and path context.
- Preserve privacy; do not log full sensitive local paths unless scrubbed.
- Distinguish conversion failure, merge failure, output file missing, interrupted app/session, and upstream media stream failure.

Acceptance criteria:

- Future ffmpeg failures are diagnosable from backend telemetry without requiring user to manually send local logs.
- `unknown` and generic `Download failed` decrease for post-process cases.

### P0 — Disk / File-System Preflight

Status: active.

Evidence:

- Rolling 24h `diskFull`: 6.
- Rolling 168h `diskFull`: 47.
- Related messages include `No space left on device`, output-file-missing, rename failure, and file in use on Windows.

Required work:

- Preflight free disk space before large download/conversion.
- Surface clear disk-space message.
- Stop retry loops when disk is full.
- Handle Windows file-in-use rename errors safely.

Acceptance criteria:

- Disk-full cases become user-actionable and do not repeat in tight loops.

### P0 — Player Disposed

Status: active.

Evidence:

- Rolling 24h: 21 records.
- Latest active groups:
  - high, 47 crashes / 10 devices, versions `1.6.2,1.6.5`.
  - high, 51 crashes / 7 devices, versions `1.6.2,1.6.5,1.3.8,1.6.3`.
  - high, 105 crashes / 17 devices in rolling 72h group set.
- Main message: `Assertion failed: "[Player] has been disposed"`.

Required work:

- Verify current player safety hardening is included in the next release artifact.
- Inspect current stack groups for paths not covered by existing `PlayerSafety`/safe-call work.
- Patch exact missed callsites only.

Acceptance criteria:

- No new `Player has been disposed` stack paths after artifact rollout.

### P0 — Ref / Context After Dispose

Status: active.

Evidence:

- Active group: 33 crashes / 18 devices.
- Versions: `1.6.2,1.6.5,1.3.8,1.3.7`.
- Last seen: 2026-05-11.
- Message: `Bad state: Cannot use "ref" after the widget was disposed.`

Required work:

- Verify lifecycle sweep commit is included in the next artifact.
- Inspect new stack paths before adding broad defensive code.
- Add targeted tests for uncovered async UI paths.

Acceptance criteria:

- No fresh stack paths after artifact rollout.

### P1 — Windows SVG Asset Packaging Residue

Status: still active, but lower rolling 24h volume than 2026-05-06.

Evidence:

- Rolling 24h contains missing SVG records for `youtube.svg`, `tiktok.svg`, `facebook.svg`, `instagram.svg`, `reddit.svg`, `x.svg`, `other.svg`, `pinterest.svg`.
- Active groups:
  - `youtube.svg`: 79 crashes / 10 devices.
  - `tiktok.svg`: 86 crashes / 13 devices.
  - several other platform SVG groups around 26-30 crashes / 10 devices.
- Main version: VidCombo 1.6.5.

Required work:

- Validate built Windows artifact, not only source tree.
- Keep release gate that checks `data/flutter_assets/assets/icons/platforms/*.svg`.
- Ensure next VidCombo Windows installer is built from a commit with this gate and passes it.

Acceptance criteria:

- Next artifact cannot be uploaded if platform SVG assets are missing.

### P1 — WebView Creation Fallback

Status: active.

Evidence:

- Rolling 72h includes `PlatformException(0, Cannot create the InAppWebView instance!, null, null)`.
- Group count seen: 31 crashes / affected devices in historical active groups.

Required work:

- Add graceful fallback around WebView creation.
- If WebView cannot start, show recovery UI instead of app crash.
- Keep logging breadcrumbs, but do not rely on logging alone.

Acceptance criteria:

- Native WebView creation failure becomes recoverable.

### P1 — Runtime Font / Network Degradation

Status: active.

Evidence:

- Rolling 48h/72h include multiple `Failed to load font with url https://fonts.gstatic.com/...` exceptions.
- Socket timeout groups to `i.ytimg.com` remain active.
- One `Too many open files` network/socket case appears.

Required work:

- Ensure production artifacts do not runtime-fetch Google Fonts for critical UI.
- Degrade remote image/font/thumbnail/network fetch failures to placeholders/non-fatal telemetry.
- Audit connection/file handle lifecycle for repeated thumbnail/network fetches.

Acceptance criteria:

- Font and remote image/network failures do not crash or pollute crash groups as fatal app failures.

### P1 — Clipboard Windows Crash

Status: active in 168h, not dominant in 24h.

Evidence:

- Rolling 168h includes 37 `PlatformException(Clipboard error, Unable to open clipboard, 5, null)` records.

Required work:

- Centralize clipboard access or wrap all `Clipboard.getData/setData` calls.
- Degrade safely when Windows clipboard is locked/unavailable.

Acceptance criteria:

- Clipboard failures become non-fatal and user-actionable if needed.

### P1 — SQLite / DB Critical Residue

Status: active in 168h, not rolling 24h dominant.

Evidence:

- Rolling 168h includes 6 `SqliteException(517): database is locked`.
- Historical critical groups still exist.

Required work:

- Verify WAL/busy timeout is active in production artifact.
- Audit DB open directory creation, permission failure handling, and concurrent writer behavior.
- Do not silently drop writes.

Acceptance criteria:

- DB open/write failures are either recovered or surfaced with safe recovery UX.

### P2 — UI/Layout/Small Crash Groups

Status: active but lower priority.

Evidence:

- `RenderFlex overflow`, `RenderBox`/layout assertions, null-check operator, provider mutation during build.
- Some are older-version residue; inspect stack before patching.

Required work:

- Patch exact stack paths only.
- Avoid broad rewrites.

## Bugs / Tickets

Open bugs: 14, all still `new`.

Newer notable bugs:

- 2026-05-09: VidCombo 1.6.5 Windows, YouTube `loginRequired`.
- 2026-05-08: VidCombo 1.6.5 Windows, YouTube `loginRequired`.
- 2026-05-07: VidCombo 1.6.5 Windows, `Video Download`.
- 2026-05-07: VidCombo 1.6.5 Windows, Korean report roughly meaning app closes immediately after pressing X post-update.
- Older VidCombo 1.6.5 bugs remain for YouTube `unknown`, `ffmpegError`, and `yt-dlp error`.

Open Go tickets: 6.

- 2026-05-03: high, `Download stop due to log in error`.
- 2026-05-03: medium, `download just audio`.
- 2026-04-25: medium, `can not download`.
- 2026-04-22: high, `How to down load on vidcombo`.
- Older general/test tickets remain.

Admin hygiene:

- Bugs should not all remain `new`; triage into accepted / fixed in next / needs user data / stale.

## Legacy VidCombo Feedback

Latest legacy feedback page check:

- #69, 2026-05-06, replied: user confusion/complaint about downloader behavior. Not a clear crash report.
- #58, 2026-04-28, pending: paid Windows 11 user cannot install/update successfully after required update. This is an installer/update support risk.
- #47, 2026-04-21, pending: license key invalid. Treat as license/support/backend entitlement unless app evidence proves otherwise.

Do not include customer emails, license keys, or subscription IDs in agent handoff.

## Revenue / Premium

Premium:

- Total licenses: 19.
- Active licenses: 19.
- Expired: 0.
- Cancelled: 0.
- Stripe count: 17.
- Crypto count: 0.
- Churn: 0.

Revenue:

- Last 30d total: $887.11.
- Month-to-date: $175.69.
- Today at snapshot: $6.99.
- Refunds: $0.
- Svid month-to-date: $7.99.
- VidCombo month-to-date: $167.70.
- VidCombo continues to carry revenue growth.

Business note:

- Revenue movement is positive, but do not let it hide the download reliability regression.

## Non-Codebase / Do Not Implement Blindly

- Setting `is_mandatory=true` is a release/ops decision, not a code patch.
- Legacy feedback #47 and #58 require support/license/installer verification before code changes.
- Old bugs/tickets should be triaged administratively before using them as code tasks.
- Revenue strategy is not a runtime bug fix.
- Backend `dirty` build identity is deploy pipeline/ops unless backend changes are explicitly requested.
- VidCombo 1.6.6 device records without release records require release/admin verification.

## Blind Spots

This backend snapshot cannot prove:

- App freezes/hangs that do not emit telemetry.
- Users who crash before device registration or before crash upload.
- Runtime issues on devices that never reconnect.
- Exact Windows 10 vs Windows 11 split.
- Android telemetry unless the Android app reports into the same backend pipeline.
- Exact root cause for `unknown` download errors until classifier/metadata improves.

## Final CTO State

Production is alive and growing, but not stable enough to call clean.

Backend is healthy. The current highest product risk is download/extract reliability, especially VidCombo 1.6.5 + YouTube. The current highest runtime risks are player disposed, ref-after-dispose, remaining Windows asset packaging residue, WebView creation failure, and runtime font/network degradation.

Agents should execute the Priority Codebase Task Queue above, starting with download reliability and lifecycle/runtime crash residue. Do not treat dry-run/internal tester artifacts as production release sign-off until full test gate and production release records are clean.
