# Pass 2 — Infrastructure + Source-Dist Divergence Finding

Date: 2026-04-24
Auditor: Verification CTO
Scope: Pass 2 — tool hardening + critical new finding

Raw outputs:
- [`2026-04-24-pass2-audit-static-raw.md`](./2026-04-24-pass2-audit-static-raw.md)
- [`2026-04-24-pass2-audit-build-raw.md`](./2026-04-24-pass2-audit-build-raw.md)

## Executive Summary

Pass 2 delivered verification infrastructure upgrades + uncovered a critical finding that reframes Pass 1's scorecard: **source tree and dist tree diverge substantially on forbidden claims**. Dist is clean; source is dirty. If anyone rebuilds + deploys in current state, 60 page-violations ship that are not in current dist.

**Verdict remains NO-GO for rebuild + deploy.** Rsync-dist-as-is deploy is technically possible but not recommended without resolving source state.

## Infrastructure Delivered

### 1. Shared Forbidden-Claims File

`website/docs/forbidden-claims.txt` is now a shared source of truth between Landing CTO and Verification CTO. Landing CTO adopted the file with a simpler one-pattern-per-line format (preferable — my original `pattern|severity|reason` was over-engineered). Landing CTO also contributed 2 new patterns that directly address baseline line 179 (mobile/cloud implied scope):

- `everything syncs automatically` — implies cloud sync that SSvid doesn't do
- `cross-platform sync` — same concern

Both audit systems now read from this file. Format evolution without coordination friction — this is exactly what the protocol should enable.

### 2. Python Metadata Extractor

`scripts/verify-landing/lib/extract-metadata.py` handles multi-line H1, nested tags, and HTML entities. Fixed Pass 1 limitation W5. Example extraction on homepage:

```
H1:    Save Any Video. Full Quality. On Your Device.
title: SSvid — Save Videos on Desktop and Mobile
og:    SSvid — Save Videos on Desktop and Mobile (match)
tw:    SSvid — Save Videos on Desktop and Mobile (match)
lang:  en
```

H1 audit now correctly identifies EN homepage as using "Save" verb per baseline. Pass 1 scored this 40% due to broken extractor; actual score closer to 80% for Decision 1 on English homepage.

### 3. Build Audit (`audit-build.sh`)

Implements the source-dist divergence check. Does NOT run build — reads existing dist state. Checks:

- Dist presence + freshness (via mtime)
- Source-vs-dist forbidden claim divergence per pattern
- Sitemap XML validity + URL entry count
- Service worker cache version (attempted match to pubspec.yaml)
- Critical asset presence (index.html, robots.txt, sitemap.xml, site.webmanifest, sw.js, og:image)
- hreflang coverage on homepage

### 4. Audit-Static Improvements

- Check C now reads from `forbidden-claims.txt` instead of hardcoded list
- Check D (H1 spine) uses Python extractor — works on all 16 home pages
- Check E (verb system) scoped to English only; per-locale verb audit deferred to Pass 3 with a proper translation map
- Fixed bash arithmetic bug with `grep -c` zero-match exit code

## Critical Finding: Source-Dist Divergence

| Pattern | Source | Dist | Divergence | Severity |
|---------|-------:|-----:|-----------:|:---------|
| `virus-free` | **32** | 0 | **+32** | FAIL |
| `fastest video downloader` | **26** | 0 | **+26** | FAIL |
| `best video downloader` | **2** | 0 | **+2** | FAIL |
| `2M+ users` | 0 | 0 | 0 | — |
| `30x faster` | 0 | 0 | 0 | — |
| `100% safe` | 0 | 0 | 0 | — |
| `everything syncs automatically` | 0 | 0 | 0 | — |
| `cross-platform sync` | 0 | 0 | 0 | — |

**Total source-only violations: 60 page-violations across 3 patterns.**

### What This Means

Two distinct deploy scenarios produce different risk profiles:

**Scenario A — Rsync dist as-is (no rebuild):**
- 0 forbidden claims ship
- Risk: dist may be stale relative to source (dist 2 min old, source has newer uncommitted work in `*/download/` locale dirs, `guide.html`, etc.)
- Operational risk: anyone hitting "rebuild" button before deploy undoes cleanliness

**Scenario B — Build from source then deploy:**
- 60 page-violations ship immediately
- Including homepage `Virus-free` trust badge and 26 pages with "fastest video downloader"
- This is what CI typically does

Current CI/CD builds before deploy, so **Scenario B is operative for automated releases**. Source state is the deploy-relevant state.

### Why This Happened

Best-faith reconstruction: Landing CTO produced clean copy in a recent pass, rebuilt dist from that state, then subsequent edits to source (possibly reverting some changes, possibly new unrelated drift) reintroduced violations without rebuilding dist. The gap is ~2 min old, suggesting a build happened in this session but source continued to evolve afterward.

This is not an accusation — it is a natural workflow artifact when source and dist live in the same tree without strict build-on-commit discipline.

### Remediation Options

1. **Fix source** (clean path): Landing CTO removes `virus-free` from 32 source pages, `fastest video downloader` from 26, `best video downloader` from 2. Rebuild dist. Source = dist = clean.

2. **Freeze dist + deploy from dist** (emergency path): Lock current dist snapshot, bypass rebuild step in deploy. Brittle: any future deploy MUST remember to skip rebuild. Not recommended.

3. **Both** (robust path): Fix source AND add CI assertion that build-output divergence from source > 0 fails the build. Prevents future recurrence.

**Recommended: Option 3.** Option 1 as immediate fix, Option 3 as standing guard.

## Reconciled Scorecard

Pass 1 scorecards diverged (Landing CTO 72% vs me 32%). Pass 2 resolves the divergence:

| Decision | Landing CTO (dist) | Verification CTO v1 (source) | V CTO v2 (source, fixed extractor) | Reconciled |
|----------|--------------------:|------------------------------:|------------------------------------:|-----------:|
| 1. Verb | 100% | 40% | 80% | **~80%** |
| 2. Taxonomy | 40% | 0% | 0% | **~10%** |
| 3. Hero | 57% | 25% | 40% | **~40%** |
| 4. Download IA | 83% | 50% | 50% | **~60%** |
| 5. Trust | 60% | 20% | 20% | **~25%** (source) / ~70% (dist) |
| 6. Metadata | 100% | 74% | 74% | **~80%** |
| 7. Proof | 80% | Unknown | Unknown | **Unknown** |

**Reconciled overall: ~45% (source-anchored) / ~65% (dist-anchored).**

Neither Landing CTO's 72% nor my original 32% was "correct" — they measured different surfaces. Truth is a spread because tree state is inconsistent across surfaces. The spread itself is the problem.

## Updated Blocking Issues

1. **SEO anti-pattern directories** (12 files in `en46/en80/en81/en82/en/compare/`) — unchanged from Pass 1.
2. **"Virus-free" in 32 source pages** — unchanged; must remove.
3. **"Best video downloader" in 2 source pages** — unchanged.
4. **"Fastest video downloader" in 26 source pages** — NEW in Pass 2 (not in Pass 1 forbidden list). Landing CTO's contribution caught this.
5. **Source-dist divergence** — NEW finding. Rebuild-safety broken.

## What's Better Since Pass 1

- Verification tooling matured: Python extractor works, build audit works, shared forbidden list works
- Landing CTO contributed to forbidden-claims.txt — collaboration is functioning
- Tracker regression guard confirms no GA/gtag in source currently
- Hreflang coverage on homepage = 16 tags (passes)
- Sitemap is valid XML with 81 URLs
- All critical assets present in dist
- Dist is fresh (2 min old)

## Known Tool Limitations (Pass 2 v2)

Still deferred to Pass 3+:

1. **Per-locale verb audit** (Decision 1 for non-English) — needs translation map of "Save" in each locale
2. **Hero contract 4-things-only** (Decision 3) — needs semantic analysis; only possible in Pass 3 runtime review
3. **Proof hierarchy** (Decision 7) — runtime only
4. **Taxonomy separation check** (Decision 2) — current implementation flags at sentence-level; better = semantic block-level
5. **Service worker version match** — can't extract version string from current sw.js format

## Next Pass

Pass 3 awaits Landing CTO remediation of Blocking 1-5 + verification request. On request, Verification CTO will:

- Re-run static + build audit
- Confirm source-dist convergence
- Execute runtime audit (Playwright walkthrough if tree state permits)
- Produce Step-specific verdict

If Landing CTO wants a dry-run before formal request, run `bash scripts/verify-landing/audit-static.sh` and `bash scripts/verify-landing/audit-build.sh` locally.

## Commit Status

Zero commits made by Verification CTO in Pass 2. All artifacts remain in working tree for review:

- `website/docs/forbidden-claims.txt` (Landing CTO owns, both contribute)
- `website/docs/verification-protocol.md`
- `website/docs/verification-scorecard-latest.md`
- `website/docs/verification-reports/*.md` (4 files)
- `scripts/verify-landing/audit-static.sh`
- `scripts/verify-landing/audit-build.sh`
- `scripts/verify-landing/lib/extract-metadata.py`
- `scripts/verify-landing/README.md`
- `scripts/verify-landing/audit-runtime.sh` (skeleton)
- `scripts/verify-landing/deploy-readiness.sh` (skeleton)

## Sign-off

Pass 2 complete. Infrastructure ready for Pass 3 on Landing CTO request.

Verification CTO — 2026-04-24T08:05Z
