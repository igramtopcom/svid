# Production Live Checklist — Svid + VidCombo

Snapshot: 2026-05-06 10:16 UTC+7  
Source: Go backend admin API (`api.svid.app`) + legacy VidCombo feedback admin  
Scope: telemetry/users currently connected to Svid + VidCombo production apps  
Rule: do not treat memory or old reports as current truth; this document is based on the live snapshot above.

## Executive Verdict

Backend/API is healthy. Production is not down. Users are active and revenue/licensing is still moving.

However, production app telemetry is not clean. The dominant current risk is app-side runtime/package stability on VidCombo 1.6.5, especially Windows, plus several smaller but real core-feature/download errors.

Do not report "all clear". The correct state is: backend healthy, app production usable, but latest live artifacts still have residue that must be closed by code fixes plus a new verified artifact reaching users.

## Codebase Execution Intake

This section is the handoff boundary for codebase agents. Treat it as the implementation queue. Other sections below provide evidence and operational context.

### Direct Codebase Tasks

1. Windows artifact asset integrity

- Problem: VidCombo 1.6.5 is still crashing on missing `assets/icons/platforms/*.svg`.
- Required result: release pipeline must fail if Windows bundle/installer output lacks platform SVG assets.
- Validate against built artifact, not only source tree.

2. Clipboard crash guard

- Problem: `PlatformException(Clipboard error, Unable to open clipboard, 5, null)`.
- Required result: all clipboard read/write paths degrade safely and never crash app.
- Scope: Windows first, but patch should be cross-platform safe.

3. SQLite open/write resilience

- Problem: critical `unable to open database file` and `database is locked`.
- Required result: DB directory creation/open path, WAL/busy timeout, concurrent write queue, retry/backoff, and recovery messaging are verified.
- Do not silently drop writes.

4. Lifecycle/player residue close-out

- Problem: live telemetry still shows `Player has been disposed` and `Cannot use ref after disposed`.
- Required result: ensure current hardening commits are in the next release artifact and add targeted tests for any uncovered stack paths found in crash groups.
- Do not rewrite the whole player layer unless the stack proves it is necessary.

5. WebView creation fallback

- Problem: `Cannot create the InAppWebView instance`.
- Required result: browser/WebView entrypoints fail gracefully with recovery UI instead of app crash.

6. Network/image fetch degradation

- Problem: `SocketException timeout to i.ytimg.com` is being reported as crash.
- Required result: remote thumbnail/image/network failures render placeholder and log non-fatal telemetry.

7. Download error taxonomy and UX

- Problem: too many core-feature failures are classified as `unknown`.
- Required result: classify YouTube loginRequired, diskFull, ffmpegError, formatUnavailable, accessDenied, interrupted conversion, output-file-missing, and network errors into actionable user-facing states.

8. FFmpeg/conversion failure diagnostics

- Problem: `Postprocessing: Conversion failed` lacks enough root-cause data.
- Required result: capture safe stderr tail, command phase, binary version, input/output metadata, and path context without leaking sensitive data.

9. Disk-space preflight

- Problem: repeated `No space left on device`.
- Required result: preflight free disk space before large download/conversion and stop retry loops with a clear user message.

10. Null-check/layout/provider small crash groups

- Problem: low-count but real app bugs: null check, render assertions, provider mutation during build.
- Required result: inspect stack traces and patch exact callsites only.

### Non-Codebase / Do Not Implement Blindly

- Revenue/premium strategy is context, not a runtime bug fix.
- Legacy VidCombo #66 is subscription renewal support, not app code.
- Legacy VidCombo #47 is license/support/backend entitlement until proven otherwise.
- Old tickets/test bugs should be triaged administratively before code changes.
- `is_mandatory=true` release policy is operational, not a code patch.
- VidCombo 1.6.6 device records without release records require release/admin verification before code changes.
- Backend `dirty` build identity is deploy pipeline/ops unless backend repo changes are explicitly requested.

## Data Coverage

- Health: `/health`, `/version`, `/admin/v1/system/health`
- Dashboard: `/admin/v1/dashboard/comprehensive`, `/admin/v1/dashboard/brand-comparison`
- Devices: `/admin/v1/devices`, 27 pages fetched
- Crashes: `/admin/v1/crashes`, 60 pages fetched
- Crash groups: `/admin/v1/crash-groups`, 2 pages fetched
- Download errors: `/admin/v1/analytics/download-errors`, 18 pages fetched
- Download error stats: all brands + Svid + VidCombo
- Bugs: `/admin/v1/bugs`, `/admin/v1/bugs/stats`
- Tickets: `/admin/v1/tickets`
- Releases: `/admin/v1/releases`
- Premium/revenue: `/admin/v1/premium/stats`, `/admin/v1/finance/revenue`
- Legacy VidCombo support: `quantri.vidcombo.com/admin/feedbacks`

## Backend Health Checklist

Status: OK

- Database: connected
- System health: OK
- DB pool: open 3, idle 3
- Memory: about 16 MB
- Goroutines: 19
- Uptime: about 142 hours
- Backend version: `v1.6.1-85-gb37334fb-dirty`
- Git SHA: `b37334fbb7a5e87546920f5f44d2b304a4d98233`

Risks:

- Backend build identity still contains `dirty`. This is not a user-facing outage, but it is still an operational traceability smell.
- Backend itself does not show signs of API/database outage in this snapshot.

## Device / Adoption Checklist

Total devices: 2,659 by dashboard, 2,662 from full paginated fetch timing drift.

All brands:

- Active today: 45
- Active 7d: 1,233
- New today: 13
- Rolling 24h active from device records: 363
- Windows: about 2,190
- macOS: about 469

Svid:

- Total devices: about 521
- Active today: 9
- Active 7d: 174
- Rolling 24h active: 51
- Latest active version: 1.3.8 has 91 active 7d, 24 active 24h

VidCombo:

- Total devices: about 2,138
- Active today: 36
- Active 7d: 1,059
- Rolling 24h active: 312
- VidCombo 1.6.5: 864 total, 823 active 7d, 248 active 24h
- VidCombo 1.6.2: 1,015 total, 182 active 7d, 45 active 24h
- VidCombo 1.6.1: 185 total, 40 active 7d, 13 active 24h
- VidCombo 1.6.0: 41 total, 4 active 7d, 2 active 24h
- VidCombo 1.6.6: 3 devices, no release record found

Risks:

- 1.6.5 adoption is high, so any 1.6.5 artifact issue has real production blast radius.
- 1.6.2 is still a large installed cohort, so old-version residue will continue appearing.
- 1.6.6 device records exist without a matching release record. Treat this as test/internal or release-registration gap until proven otherwise.
- Dashboard OS metadata currently does not reliably distinguish Windows 10 vs Windows 11; most Windows devices report Windows 10-style version strings.

## Release Channel Checklist

Active latest records:

- Svid 1.3.8 Windows: active, mandatory false, published 2026-04-28
- Svid 1.3.8 macOS: active, mandatory false, published 2026-04-28
- VidCombo 1.6.5 Windows: active, mandatory false, published 2026-04-28
- VidCombo 1.6.5 macOS: active, mandatory false, published 2026-04-28

Risks:

- `mandatory=false` means users can remain on old builds.
- Many old releases are still `is_active=true`, including older Svid and VidCombo versions. If the update-check contract selects latest correctly this is acceptable, but operationally it increases ambiguity.
- No backend release record for VidCombo 1.6.6 despite 3 devices.

## Crash / Runtime Checklist

Rolling 24h crash records: 189

- VidCombo: 177
- Svid: 12
- VidCombo 1.6.5: 177
- Svid 1.3.7: 10
- Svid 1.3.5: 2
- Windows: 176
- macOS: 13
- Severity: 9 critical, 40 high, 136 medium, 4 low

Rolling 72h crash records: 332

- VidCombo: 319
- Svid: 13
- VidCombo 1.6.5: 318
- Windows: 318
- macOS: 14

Rolling 168h crash records: 479

- VidCombo: 439
- Svid: 40
- VidCombo 1.6.5: 416
- Svid 1.3.7: 32
- VidCombo 1.6.2: 22
- Svid 1.3.8: 6

### P0/P1 Current Runtime Watchlist

1. Missing SVG platform assets

- Status: active in production
- Severity in backend: medium, but practical impact can be high because it crashes UI paths repeatedly.
- Main version: VidCombo 1.6.5
- Main platform: Windows
- Examples: `youtube.svg`, `tiktok.svg`, `facebook.svg`, `instagram.svg`, `reddit.svg`, `x.svg`, `other.svg`, `pinterest.svg`
- 24h examples: `youtube.svg` alone 41 records; multiple other SVGs 5-6 records each in rolling 24h
- Group examples: `tiktok.svg` 75 crashes / 9 devices; `youtube.svg` 67 crashes / 6 devices
- Assessment: app packaging/artifact issue, not backend.
- Codebase mapping: CI/package gate already exists in current codebase, but users on old artifact will continue to crash until a new verified artifact reaches them.
- Action: next release artifact must verify `data/flutter_assets/assets/icons/platforms/*.svg` after build/sign/installer.

2. Clipboard Windows error

- Status: new/current production signal
- Message: `PlatformException(Clipboard error, Unable to open clipboard, 5, null)`
- Severity: high
- Count: 38 crashes / 2 devices in crash group
- Current window: 37 records in rolling 24h
- Main version: VidCombo 1.6.5
- Assessment: real Windows runtime issue, likely environment/clipboard-lock related but app must guard/degrade.
- Action: code audit all clipboard read/write paths; wrap platform clipboard calls defensively; do not let clipboard failure crash app.

3. SQLite critical: unable to open DB / database locked

- Status: active
- Messages:
  - `SqliteException(14): while opening the database, unable to open database file`
  - `SqliteException(517): database is locked`
- Severity: critical in backend
- Counts:
  - unable-open group: 18 crashes / 6 devices
  - database-locked group: 6 crashes / 1 device
- Versions include: 1.6.5, 1.6.2, 1.3.5, 1.3.6
- Assessment: real data-layer stability risk. Some prior WAL/busy-timeout work exists, but live telemetry still has DB failures.
- Action: audit DB open path, migration/open directory creation, permissions, concurrent write queue, and retry/backoff semantics.

4. Player disposed

- Status: active
- Message: `Assertion failed: "[Player] has been disposed"`
- Severity: high
- Group: 88 crashes / 15 devices
- Versions: 1.6.2, 1.6.3, 1.6.4, 1.6.5, 1.3.8
- Last seen: 2026-05-06
- Assessment: current codebase has async player guard hardening, but production telemetry still shows live artifact/users hitting the class.
- Action: ensure hardening commit is in next artifact; after release, verify no new stack paths remain.

5. Ref/context after dispose

- Status: active
- Message: `Bad state: Cannot use "ref" after the widget was disposed.`
- Severity: medium
- Group: 18 crashes / 12 devices
- Versions: 1.6.2, 1.6.5, 1.3.8
- Last seen: 2026-05-05
- Assessment: current codebase has `d7ce688d` sweep for this class; live close-out requires artifact rollout and telemetry confirmation.
- Action: next release must include lifecycle hardening; monitor for fresh stack traces not covered by sweep.

6. InAppWebView creation failure

- Status: active
- Message: `PlatformException(0, Cannot create the InAppWebView instance!, null, null)`
- Severity: high
- Group: 26 crashes / 11 devices
- Versions: 1.6.2, 1.3.5, 1.6.5
- Last seen: 2026-05-05
- Assessment: real WebView/native-view failure. Likely environment/native plugin/runtime constraints.
- Action: add graceful fallback around WebView creation and user-facing recovery path.

7. Socket timeout to YouTube image host

- Status: active
- Message: `SocketException timeout to i.ytimg.com`
- Severity: medium
- Group: 111 crashes / 11 devices
- Versions: 1.6.2, 1.3.5, 1.6.3, 1.6.5
- Assessment: network/environment issue should not be app-crashing.
- Action: image/network fetch paths must degrade to placeholders and log non-fatal telemetry.

8. Null check operator used on null value

- Status: active
- Severity: medium
- Count: 2 crashes / 2 devices
- Versions: 1.6.2, 1.6.5
- Last seen: 2026-05-06
- Assessment: small count but real app bug class.
- Action: inspect stack trace group and patch exact null assertion path.

9. Flutter layout/render assertions

- Status: active, mostly low/medium
- Messages:
  - `RenderFlex overflowed`
  - `RenderBox was not laid out`
  - `Leading widget consumes the entire tile width`
  - Box constraints assertion
- Versions include: 1.3.7, older and latest residues
- Assessment: may be non-fatal in debug but telemetry treats as crash/report. UI resilience issue.
- Action: fix layouts if stack traces point to production widgets; otherwise lower severity/classify.

10. Provider modification during build / AutocompleteNotifier listener exception

- Status: active, small count
- Versions: 1.3.7
- Assessment: state lifecycle issue. Could be older artifact or current code depending branch lineage.
- Action: inspect stack and avoid provider mutation during build callbacks.

## Core Feature / Download / Extract Checklist

Dashboard:

- Downloads today: 214
- Download success rate: 95%
- Download errors today by dashboard day bucket: 10
- Total download errors: 1,762

Rolling 24h raw download errors: 164

- VidCombo: 162
- Svid: 2
- VidCombo 1.6.5: 158
- VidCombo 1.6.2: 3
- Svid 1.3.8: 2
- VidCombo 1.6.1: 1

Rolling 72h raw download errors: 506

- VidCombo: 459
- Svid: 47
- VidCombo 1.6.5: 392
- VidCombo 1.6.2: 59
- Svid 1.3.8: 35

Rolling 168h raw download errors: 946

- VidCombo: 831
- Svid: 115
- VidCombo 1.6.5: 718
- VidCombo 1.6.2: 88
- Svid 1.3.8: 87

### Download Error Categories

1. YouTube login/bot-check

- Status: active
- Code: `loginRequired`
- Rolling 24h: 43
- Rolling 72h: 168
- Rolling 168h: 301
- Message: `Sign in to confirm you're not a bot`
- Assessment: real user-facing failure, often upstream/account/IP/cookies dependent. Not full-system outage.
- Action: improve cookies UX, force-update yt-dlp guidance, classify clearly, avoid generic "unknown".

2. Unknown download/extraction/post-process

- Status: active
- Rolling 24h: 83
- Rolling 72h: 202
- Rolling 168h: 393
- Examples:
  - `Output file not found after download`
  - `App was interrupted during conversion`
  - video unavailable
  - SSL/decryption/connection aborted
- Assessment: too much is classified as `unknown`; this hides root cause quality.
- Action: improve classifier and attach phase-specific metadata. Unknown should become actionable categories.

3. Disk full / no space left

- Status: active
- Rolling 24h: 17
- Rolling 72h: 29
- Rolling 168h: 32
- Message: `No space left on device`
- Assessment: user environment, but core UX must make it obvious and recoverable.
- Action: preflight free-space check before large downloads/conversions; show clear UI; stop retry loop.

4. FFmpeg/conversion failure

- Status: active
- Rolling 24h: 10
- Rolling 72h: 38
- Rolling 168h: 48
- Message: `Postprocessing: Conversion failed`
- Assessment: real core feature failure class.
- Action: capture command args, input format, output path, ffmpeg stderr tail, binary version; add fallback or clearer failure.

5. Format unavailable

- Status: active
- Rolling 24h: 3
- Rolling 72h: 12
- Rolling 168h: 39
- Assessment: partly upstream/media availability, partly UX selection issue.
- Action: fallback to nearest format and explain when requested quality is unavailable.

6. Access denied / HTTP 403

- Status: active
- Rolling 24h: 2
- Rolling 72h: 8
- Rolling 168h: 20
- Assessment: upstream permission/rate/cookies.
- Action: classify separately from generic failure; suggest cookies/login where relevant.

7. Facebook/pathNotFound

- Status: lower than previous days but still present
- Rolling 24h: 2 pathNotFound total
- Rolling 168h: 75 pathNotFound total, mostly Facebook historically
- Assessment: current 24h not dominant, but still on watchlist.
- Action: keep yt-dlp/gallery-dl update path healthy and classifier precise.

8. Network timeout / connection refused

- Status: active
- Rolling 168h: networkTimeout 19, connectionRefused 8
- Assessment: environment/network/upstream. Should not crash app.
- Action: retry/backoff and user-facing network message.

Feature verdict:

- There are real download/extract/conversion failures in production.
- There is no evidence that the entire download feature is down.
- Current core-feature risk is concentrated around VidCombo 1.6.5, YouTube, and post-process/conversion classification.

## Open Bugs Checklist

All 10 open bugs remain `new`.

- 2026-05-04: VidCombo 1.6.5 Windows, YouTube unknown, Japanese video title
- 2026-05-04: VidCombo 1.6.5 Windows, YouTube ffmpegError, dance festival video
- 2026-05-02: VidCombo 1.6.5 macOS, yt-dlp error
- 2026-04-25: VidCombo 1.6.2 macOS, cannot download
- 2026-04-25: VidCombo 1.6.2 macOS, Japanese cannot download
- 2026-04-23: VidCombo 1.6.2 macOS, YouTube loginRequired
- 2026-04-23: VidCombo 1.6.2 macOS, cannot download
- 2026-04-23: VidCombo 1.6.2 Windows, Chinese cannot download
- 2026-04-18: Svid 1.3.5 Windows, YouTube unknown
- 2026-03-25: Svid 1.2.0 macOS, CTO audit test

Risks:

- Bugs are not being triaged/closed in admin state; all remain `new`.
- Some old bugs are stale but still pollute operational view.

## Open Tickets Checklist

Open tickets: 6

- 2026-05-03: high, `Download stop due to log in error`
- 2026-05-03: medium, `download just audio`
- 2026-04-25: medium, `can not download`
- 2026-04-22: high, `How to down load on vidcombo`
- 2026-03-24: medium, `questions`
- 2026-03-23: medium, `test1`

Risks:

- No new Go ticket today.
- Two May 3 tickets are directly feature/support relevant.
- Old test/general tickets should be closed or classified to reduce noise.

## Legacy VidCombo Feedback Checklist

Latest legacy feedback:

- #66, 2026-05-05: subscription/license renewal support. Not app crash/runtime.
- #47, 2026-04-21: license key invalid, still pending. Related to VidCombo Android/license migration/support, not proven desktop runtime bug.

Risks:

- Legacy admin remains a separate support channel, so Go backend alone is not complete support visibility.
- #47 should stay on Android/license migration watchlist until closed by support/backend entitlement audit.

## Revenue / Premium Checklist

Premium:

- Total licenses: 17
- Active licenses: 17
- Expired: 0
- Cancelled: 0
- Stripe count: 15
- Crypto count: 0
- Churn: 0

Revenue:

- Last 30d total: $817.21
- Month-to-date: $105.79
- Today: $0 at snapshot time
- Refunds: $0
- Svid month-to-date: $7.99
- VidCombo month-to-date: $97.80
- 2026-05-05 revenue: $55.86 from 3 payments, all VidCombo

Risks:

- Svid monetization remains weak compared with VidCombo.
- No refund signal in this snapshot.

## Prioritized Action Checklist

P0 — must not ship/release blindly:

- Verify next Windows artifact contains all platform SVG assets after build/sign/installer.
- Fix or guard Clipboard Windows crash.
- Audit SQLite open/write critical failures.
- Ensure player/ref lifecycle hardening commits are included in the artifact that users receive.

P1 — core feature reliability:

- Improve YouTube loginRequired/cookies UX and classification.
- Improve `unknown` download error taxonomy.
- Capture ffmpeg stderr/args/version for conversion failures.
- Add disk-space preflight before large downloads/conversions.
- Add WebView creation fallback instead of fatal crash.

P2 — operations/admin hygiene:

- Resolve/reclassify all open bugs currently stuck at `new`.
- Close stale/test tickets.
- Decide whether older release records should remain active.
- Investigate 1.6.6 device records without release records.
- Clean backend build traceability from `dirty`.

## Blind Spots

These cannot be claimed clean from this backend snapshot alone:

- Users who never reach backend because app crashes before registration/telemetry.
- Local freezes/hangs that do not emit crash records.
- Windows-specific runtime details not captured in `os_version` accurately.
- Android app telemetry if not connected to the same Go backend crash/download pipeline.
- Legacy VidCombo support tickets beyond accessible feedback pages.
- Exact root cause for each `unknown` download error until classifier/metadata improves.

## Final State

Production is live and usable, but not clean.

Backend is healthy. The real work is app artifact/runtime hardening plus feature-error taxonomy. The highest current risk is VidCombo 1.6.5 production artifact quality, especially Windows, followed by Clipboard/SQLite/lifecycle crash classes and YouTube/ffmpeg download reliability.
