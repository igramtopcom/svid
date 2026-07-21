# Production Live Deep Audit

> Historical snapshot only. For current production-live status and codebase execution intake, use [production-live-checklist-2026-05-06.md](production-live-checklist-2026-05-06.md).

Primary snapshot window: `2026-04-27 18:37:41 +07` to `2026-04-27 19:12:00 +07`  
System scope: `SSvid app`, `VidCombo app`, `backend dashboard API`, and `legacy VidCombo admin feedback surface`

Important note: production counters moved slightly during the audit window. When two surfaces disagree, this document treats `raw device / crash / ticket / feedback surfaces` as the source of truth and treats dashboard cards as derived views that may still have definition drift.

## Executive Summary

The system is live and serving users. Backend health is good, device growth is still strong, and the admin/dashboard API is responding across all critical surfaces today. However, production is not in a clean steady state.

The most serious issue is still `VidCombo 1.6.3` shipping a real crash on local legacy thumbnails. Raw crash records confirm new `1.6.3` reports on `2026-04-27`, so this is not only a historical group attribution problem. `SSvid 1.3.6` currently looks safer, but the sample is still small.

The second major issue is `download reliability and tooling quality`. The dashboard shows high download usage, but the error surface is still large and user feedback confirms real failures such as `gallery-dl` setup problems and generic `cannot download` reports.

The third issue is `observability quality`. The dashboard is operational again, but several metrics still disagree with each other, especially download success and active/new device counts. This means the system is observable, but not fully trustworthy at the metric-definition level.

## Methodology

This audit is based on live data from:

- `GET /health`
- `GET /admin/v1/analytics/stats`
- `GET /admin/v1/analytics/top-events`
- `GET /admin/v1/analytics/downloads`
- `GET /admin/v1/analytics/download-errors/stats`
- `GET /admin/v1/premium/stats`
- `GET /admin/v1/transactions/stats`
- `GET /admin/v1/subscriptions/stats`
- `GET /admin/v1/invoices/stats`
- `GET /admin/v1/feedback/stats`
- `GET /admin/v1/ratings/stats`
- `GET /admin/v1/bugs/stats`
- `GET /admin/v1/crash-groups/stats`
- `GET /admin/v1/dashboard/comprehensive`
- `GET /admin/v1/dashboard/brand-comparison`
- `GET /admin/v1/dashboard/trends?days=7`
- `GET /admin/v1/dashboard/activity?limit=30`
- Raw list endpoints for `devices`, `tickets`, `bugs`, `crash-groups`, and `crashes`
- Legacy VidCombo admin feedback inbox at `https://quantri.vidcombo.com/admin/feedbacks`

## Current Live State

### Backend and Control Plane

- Health: `healthy`
- Database: `connected`
- Runtime: `19 goroutines`, `22 MB`
- Uptime: about `45h12m`
- Tables: `1718 devices`, `12 licenses`, `4 tickets`, `102 transactions`, `7 bug reports`
- Admin/dashboard surfaces checked: `20/20 healthy`

Positive change versus earlier snapshots:

- Summary endpoints are no longer broadly rate-limited.
- The admin dashboard is usable again for daily operations.

Remaining backend risks:

- `/health` still reports `version: dev`
- `/health` still reports `git_sha: unknown`

This is a release traceability gap. Production should identify the exact artifact or commit running.

### Rollout and Adoption

- Total devices: `1718`
- By brand: `1285 VidCombo`, `433 SSvid`
- Active today from raw device timestamps: `199`
- New today from raw device timestamps: `70`

Version adoption:

- `VidCombo 1.6.2`: `1005 devices`
- `VidCombo 1.6.3`: `36 devices`
- `SSvid 1.3.6`: `24 devices`

Latest 50 device mix:

- `36` are `VidCombo 1.6.2`
- `5` are `VidCombo 1.6.3`
- `2` are `SSvid 1.3.6`

Interpretation:

- The new releases are live.
- `VidCombo 1.6.3` and `SSvid 1.3.6` are not yet the dominant production cohorts.
- Most real user traffic is still coming from `VidCombo 1.6.2`.

## Critical Findings

### P0: VidCombo 1.6.3 still crashes on legacy thumbnail paths

This is the most important production issue today.

Evidence:

- Active grouped incident: `2454 crashes`
- Minimum affected devices: `17`
- Latest grouped last-seen: `2026-04-27 12:10:02 +02`
- Grouped versions: `1.6.2,1.6.3`
- Title: `Invalid argument(s): No host specified in URI ... legacy_thumbnails/...`

Raw crash evidence confirms this is not just a grouping artifact:

- In the latest raw crash records, `1.6.3` reports exist directly.
- The latest sampled `1.6.3` crashes are on `macOS`.
- One raw sample shows `99` of the latest `1.6.3` crash records carrying the same local-file URI issue.

Likely root cause:

- A still-live UI path is rendering local thumbnail paths through `NetworkImage` / `DecorationImage`.
- The strongest known suspect remains [new_tab_page.dart](/Users/macos/development/download-apps/desktop-apps/snakeloader/lib/features/browser/presentation/widgets/new_tab_page.dart:581), where local thumbnail strings are still fed into `NetworkImage(d.thumbnail!)`.

Operational interpretation:

- Either the previous fix did not fully cover every render path.
- Or the release artifact did not contain the intended fix set.
- Or both.

This issue alone is enough to keep `VidCombo` out of a “production clean” state.

### P1: Playback lifecycle crashes still active on VidCombo

Grouped crash signals still show:

- `Assertion failed: "[Player] has been disposed"`
- `68 crashes`
- Active into `2026-04-27`

This is lower priority than `legacy_thumbnails`, but it still means playback stability is not closed.

### P1: Download and setup reliability still hurts users

Dashboard stats:

- Total downloads: `11154`
- Success count: `4785`
- Error count: `607`
- Download success rate from downloads endpoint: `42.9%`

Top structured download errors:

- `unknown`: `300`
- `loginRequired`: `254`
- `pathNotFound`: `49`
- `formatUnavailable`: `24`
- `accessDenied`: `18`
- `ffmpegError`: `17`
- `rateLimited`: `17`

Top error platform:

- `youtube`: `612` errors

Legacy VidCombo support confirms these are not only telemetry artifacts:

- `Setup fails - gallery-dl` — `2026-04-25 13:18`, pending
- `Gallery-dl not found!` — `2026-04-24 23:34`, pending
- `Update issue` — `2026-04-26 14:18`, pending

Current bug and ticket signals also align:

- Ticket: `can not download`
- Ticket: `How to down load on vidcombo`
- Bug reports: `can not download`, `Cannot download`, `ダウンロードできません`, `无法下载视频`

Interpretation:

- Core download flows are still usable, but setup/bootstrap and platform-specific extraction are not fully stable.
- `gallery-dl`, `yt-dlp`, or related dependency/bootstrap handling remains a live risk.

## Significant Non-Critical Findings

### SSvid is healthier than VidCombo, but not clean

Positive signals:

- `SSvid 1.3.6` has `24 devices`
- No current raw evidence of a new `1.3.6` crash cluster in the latest crash page
- Launch/intake/download remain usable

Remaining issues:

- Checkout is still weak
- A grouped `RenderFlex overflow` incident remains large:
  - `425 crashes`
  - last seen `2026-04-25`

This looks more like UI/runtime noise than a broad fatal outage, but it still counts as unresolved production instability.

### Payment funnel is weak even though billing exists

Transactions:

- `102 total`
- `10 completed`
- `4 pending`
- `88 cancelled`

Billing stats:

- Total paid invoice value: `$690.45`
- Admin transaction revenue tracked: `$139.90`

Interpretation:

- Revenue is real.
- But the conversion funnel is poor.
- The invoice and transaction surfaces do not represent the same financial layer.

This is probably due to recurring subscription invoices being tracked in invoices but not mirrored 1:1 in the transaction ledger. That is operationally understandable, but it still creates confusion for decision-makers.

### Support and backlog hygiene need attention

- Open tickets: `4`
- Oldest open ticket: about `850 hours`
- Legacy VidCombo feedback queue still has unreplied payment, subscription, setup, and license issues

Representative pending subjects:

- `Update issue`
- `no me cancela el pago automatico (cancelar suscripcion)`
- `Setup fails - gallery-dl`
- `Gallery-dl not found!`
- `License Key is Invalid`
- `Hi. I'd like to a refund`

This shows the old support surface is still operationally relevant and should not be ignored.

## Observability and Data Quality Risks

### Dashboard metrics are available again, but not fully consistent

Examples:

| Metric | Raw / specialized endpoint | Dashboard surface | Risk |
| --- | ---: | ---: | --- |
| Active today | `199` | `152` | operator may under-read real usage |
| New today | `70` | `51` | growth reporting understated |
| Download errors today | `27` | `27` | aligned |
| Download success rate | `42.9%` | `90` | success metric definition is not trustworthy |

There is also small same-hour drift in total devices:

- Raw device surfaces: `1716` earlier in the audit window
- Health / dashboard surfaces: `1718` later in the audit window

That difference is acceptable for a live system. The larger metric-definition mismatches above are not.

These mismatches mean:

- The dashboard is not broken in the old way.
- But metric definitions, windows, or derivation logic still differ enough to mislead operators.

### Analytics taxonomy is still dirty

Top events include:

- `download_complete`: `4785`
- `download_completed`: `3371`
- empty `event_type`: `1293`

This means:

- event taxonomy is not normalized
- some charts are combining apples and oranges
- “success rate” and “event totals” cannot be treated as clean product analytics yet

### Crash severity classification is not meaningful

- All grouped crashes are currently `medium`

That makes severity less useful for triage and alerting.

## What Is Actually Better Than Before

- Backend stability is good.
- Admin/dashboard surfaces are reachable today.
- Release adoption has started for both new app versions.
- `SSvid 1.3.6` does not yet show a clear new P0 crash cluster.
- VidCombo launch/intake/download usage is still strong, so the app is not universally unusable.

## What Apps Need To Fix Next

### VidCombo app team

1. Close every remaining local-thumbnail render path that still routes file paths into `NetworkImage` or any network-only image provider.
2. Re-verify the release artifact actually contains the intended thumbnail fix.
3. Re-check player lifecycle handling because `Player has been disposed` is still active.
4. Re-test packaged builds with legacy imported data present, especially on `macOS`, because raw `1.6.3` crashes are showing there.

### SSvid app team

1. Audit the `RenderFlex overflow` cluster and confirm whether it is only noisy UI error reporting or a user-visible blocker.
2. Investigate why `1.3.5` still dominates support and crash residue.
3. Review checkout friction because `initiated` remains low and `completed` is still effectively zero in the recent window.

### Shared downloader / converter team

1. Investigate `gallery-dl` setup failures in packaged builds.
2. Reduce `unknown`, `pathNotFound`, and `loginRequired` error buckets.
3. Audit bootstrap/install paths for `yt-dlp`, `gallery-dl`, and `ffmpeg` on first-run environments.

### Backend / dashboard team

1. Fix metric-definition mismatches between raw surfaces and dashboard cards.
2. Normalize event taxonomy:
   - merge `download_complete` and `download_completed`
   - prevent empty `event_type`
3. Expose real production build identity in `/health`:
   - correct `version`
   - correct `git_sha`
4. Improve crash severity labeling and alert usefulness.

### Ops / support team

1. Triage the legacy VidCombo feedback queue because it still contains live customer pain.
2. Clear or reclassify stale open tickets older than one week.
3. Reconcile transaction vs invoice revenue definitions in operator-facing reports.

## Final Verdict

As of `2026-04-27`, production is live and usable, but it is not yet in a fully stable “big-tech clean” state.

The biggest blocking truth is simple:

- `VidCombo 1.6.3` is still producing real production crashes on local legacy thumbnail paths.

Secondary risks are:

- download/setup reliability
- analytics/dashboard metric inconsistency
- weak checkout funnel quality
- poor release traceability from `/health`

If this document is used as the current source of truth, the correct headline is:

`Backend is stable, SSvid is comparatively safer, but VidCombo remains the primary production risk and still needs app-side fixes before the system can be called genuinely stable.`

## Evidence Appendix

### Raw crash samples proving `VidCombo 1.6.3` is still affected

These are direct raw crash records, not only grouped aggregates:

| Time | Version | OS | Device | Error |
| --- | --- | --- | --- | --- |
| `2026-04-27T10:08:42+02:00` | `1.6.3` | `macos` | `7afcfeaa-657f-4fed-8ba3-001c497e9ad9` | `Invalid argument(s): No host specified in URI file:///Users/benma/.../legacy_thumbnails/12.jpg` |
| `2026-04-27T10:08:42+02:00` | `1.6.3` | `macos` | `7afcfeaa-657f-4fed-8ba3-001c497e9ad9` | same crash repeating in-loop |
| `2026-04-27T12:10:02+02:00` | `1.6.2` | `macos` | `73f75698-3de0-4c42-b379-9c34d2da2031` | `Invalid argument(s): No host specified in URI file:///Users/yudhaaditya/.../legacy_thumbnails/1.jpg` |

Interpretation:

- `1.6.3` is definitely producing new production crashes.
- The issue is not only a historical `1.6.2` residue.
- The repeated identical rows on the same device strongly suggest crash-loop behavior, not one-off noise.

### Legacy VidCombo support subjects still open

Recent pending subjects from the old admin surface:

- `Update issue` — `2026-04-26 14:18`
- `no me cancela el pago automatico (cancelar suscripcion)` — `2026-04-26 09:52`
- `Setup fails - gallery-dl` — `2026-04-25 13:18`
- `Feedback` — `2026-04-25 05:23`
- `Gallery-dl not found!` — `2026-04-24 23:34`
- `License Key is Invalid` — `2026-04-21 07:28`
- `Hi. I'd like to a refund` — `2026-04-21 06:28`

Interpretation:

- The legacy support surface is still operationally live.
- Setup, subscription cancellation, license, and refund friction are still real user-facing issues.
