# Smoke Matrix Runbook — Pre-Production-Complete Gate

**Status:** mandatory pre-release gate per Chairman Decision Package 2026-05-21.
**Owner:** human QA / Chairman + tester ops.
**Date:** 2026-05-21
**Pairs with:** Ultra Plan v2 commits (`8ac13311`, `65897822`, …)
**Closes when:** all cells GREEN OR documented exception with sign-off.

---

## Why this exists

The 3 commits since `db2a777f` close 3 distinct production
regressions (Facebook DASH intermediate detection, Facebook
progressive fallback, cookie precedence, cross-platform auto-save
with marker guard). Unit tests pin the contracts at the
file/function level. But the bugs that motivated these fixes were
ONLY visible at the end-to-end download level — a tester reporting
"file saved, no audio" or "downloads silently became MKV". Unit
tests do NOT exercise yt-dlp + ffmpeg + multi-window + WebView2 +
real network simultaneously.

Until this matrix is GREEN on both OSes, the branch is NOT
production-complete regardless of unit-test count.

---

## Matrix dimensions

Two axes × two flows × four platforms:

|   | **YouTube** | **Facebook** | **TikTok** | **Instagram** |
|---|---|---|---|---|
| **macOS — Floating Capture** | | | | |
| **macOS — Browser tab** | | | | |
| **Windows — Floating Capture** | | | | |
| **Windows — Browser tab** | | | | |

= **16 cells**. Each cell must pass the 4 sub-checks below.

---

## Per-cell sub-checks

For every cell, fill in:

1. **Extraction time** (seconds from URL submit → quality list visible).
2. **Final file extension** matches user pick (PICK X → GET X per
   commit `43a6701a`).
3. **Final file has audio** (ffprobe shows at least one audio
   stream when video was expected to have audio).
4. **No silent failure**: if anything fails, app shows an
   actionable error message — NOT just "Download Failed".

A cell is GREEN only when all 4 pass. YELLOW = one or more pass
but with caveats logged. RED = primary failure.

---

## URL Bank (consistent across testers)

| Platform | URL | Why |
|---|---|---|
| YouTube | `9xB8oXx4PXs` | Tester reproducer for `log.md` Incident A |
| YouTube | `dQw4w9WgXcQ` | Baseline (Rick Astley) |
| YouTube | `KK9bwTlAvgo` | ≥ 1440p, triggers commit 43a6701a recode path |
| Facebook | `facebook.com/reel/2430925864093451` | Wilson Rubio reproducer from `log.md` Incident B |
| Facebook | one current public reel | Sanity baseline |
| TikTok | one popular short video | Pre-muxed MP4 source — tests commit 43a6701a remux path |
| Instagram | one public reel (no login required) | Tests yt-dlp's IG extractor |
| Instagram | one public carousel post | Tests gallery-dl path |

If any URL is taken down between sessions, replace with a fresh
one from the same category and note it in the result CSV.

---

## Pre-flight per cell

Before running:

1. **App rebuilt from current HEAD** (`scripts/dev.sh ssvid release`
   on Mac, equivalent on Windows). Hot reload does NOT propagate
   the Phase-1b enum changes — full rebuild required.
2. **Cookies cleared** for half the cells, fresh-logged for the
   other half. Track which.
3. **Browser status** logged: which browsers are running. The
   Chrome cookie-DB-lock chain only fires when Chrome runs.
4. **App version + commit hash** logged from About page.

---

## Required passing scenarios (the bugs in scope)

A cell is RED if any of these regress:

1. **YouTube + MP4 + ≤ 1080p** → file is `.mp4`, plays in QuickTime
   / VLC, has audio. (Commit 43a6701a happy path.)
2. **YouTube + MP4 + 4K** → file is `.mp4` (NOT silent-MKV swap),
   audio is re-encoded (file plays everywhere). Recode is slow but
   succeeds. (Commit 43a6701a recode path.)
3. **YouTube + MKV + 4K** → file is `.mkv`, native VP9/Opus
   stream-copy, fast. (Happy path.)
4. **TikTok + pick MKV** → file is `.mkv` (NOT source `.mp4`).
   Commit 43a6701a `--remux-video` path.
5. **Facebook reel `2430925864093451`** → file plays with audio.
   Either DASH merge succeeds OR commit 8ac13311 progressive
   fallback kicks in and produces a `best`-quality file with
   audio. Wilson Rubio's URL.
6. **Facebook DASH intermediate detection** → if a download ends
   with `.f<id>v.mp4` orphan, it must be classified as failure
   (commit 8ac13311 regex). NOT surfaced as success.
7. **Picking AVI / MOV / M4V / FLV** → file has the picked
   extension. Commit `db2a777f` + commit 43a6701a.
8. **Cookie file present + Chrome running** → download uses the
   cookies-file (no Chrome DB-lock error). Commit 65897822 cookie
   precedence fix.
9. **In-app Facebook login → auto-save** → cookies persisted after
   user clicks Done OR auto-detect (marker guard found `c_user` +
   `xs`). Commit 65897822 cross-platform auto-save.
10. **In-app login with PARTIAL cookies** (e.g. user navigated
    away mid-flow, marker absent) → save SKIPPED, log warning,
    dialog stays open. Marker guard works.

---

## How to log results

CSV at `docs/research/smoke-matrix-results-<host>-<YYYYMMDD>.csv`:

```
os,flow,platform,url,picked_container,outcome,extension,has_audio,error_text
macos,floating,youtube,9xB8oXx4PXs,mp4,green,mp4,true,
macos,browser,youtube,KK9bwTlAvgo,mp4,green,mp4,true,
windows,floating,facebook,reel/2430925864093451,best,green,mp4,true,Progressive fallback fired
windows,browser,youtube,9xB8oXx4PXs,mp4,red,,false,HTTP 403 Forbidden after 4 cookie chain attempts
```

Submit results to Chairman + Codex before any production-complete
claim.

---

## Sign-off rules

- 16/16 GREEN → PRODUCTION-COMPLETE eligible for next release tag.
- ≥ 14/16 GREEN with documented YELLOW exceptions → Chairman
  decides whether to ship.
- < 14/16 GREEN → engineering loop continues, no production claim.

The YouTube 403 cell is allowed to remain YELLOW pending the lab
runbook outcome (`youtube-no-cookie-lab-runbook-2026-05-21.md`).
All other cells must be GREEN for production-complete.

---

## What this runbook is NOT

- Not a substitute for the unit-test suite (`fvm flutter test`).
  Unit tests run on every commit; the matrix runs once per branch
  before release.
- Not auto-runnable from CI today. The Windows host + residential
  IP + multi-window + WebView2 + real-network requirements exceed
  what GitHub Actions offers. A future investment in dedicated lab
  hardware would close this gap.
- Not for ad-hoc debugging — that's the engineer's job between
  matrix runs. The matrix records ground-truth state at a
  pre-release checkpoint only.
