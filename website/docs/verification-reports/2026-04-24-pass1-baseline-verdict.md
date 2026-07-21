# Verification Verdict — Pass 1 Baseline Snapshot

Date: 2026-04-24
Auditor: Verification CTO
Scope: `website/` source tree (excluding `src/`, `docs/`, `_archive/`, `dist/`, `node_modules/`)
Commit at audit: `5547cfa7` (branch `main`)
Tooling: `scripts/verify-landing/audit-static.sh` (v1, Pass 1 baseline)
Raw output: [`2026-04-24-pass1-audit-static-raw.md`](./2026-04-24-pass1-audit-static-raw.md)

## Overall Verdict

**NO-GO for commit / deploy.**

Status is NOT a PASS/FAIL against a specific Landing CTO request — it is a baseline snapshot of working tree as of 2026-04-24 07:45 UTC. No Step has been submitted for verification yet. This report establishes the starting line before Landing CTO executes Step 1.

3 blocking issues + 7 warnings. Strategic scorecard ~30-35% (confirms peer review estimate). Do not commit current working tree.

## Scorecard vs 7 Baseline Decisions

| # | Decision | Score | Evidence |
|---|----------|-------|----------|
| 1 | Canonical verb system (Save/Download) | **40%** | No "Keep" third-framing violations. H1 extraction bug prevented full audit (see Tool Limitations). |
| 2 | Platform taxonomy separation | **0%** | All 15 home hero pages (`index.html` + 14 locale index) blend OS + source platforms in hero. Universal violation. |
| 3 | Hero contract (4 things only) | **~25%** | Cannot static-audit fully. Landing CTO báo cáo tự thừa nhận "narrative trộn". 12 SEO anti-pattern pages exist as hero duplicates. |
| 4 | Download as first-class IA | **50%** | 12 new locale `*/download/` directories untracked = legitimate WIP. 14 pages still missing download CTA. Primary nav coverage not yet verified runtime. |
| 5 | Trust architecture (auditable claims) | **20%** | **"Virus-free" appears in 32 pages including homepage trust badge.** "Best video downloader" in 2 pages. Standalone unaudited claims. |
| 6 | Metadata discipline | **74%** | 0 title-triple mismatches ON pages that have tags. BUT 29/111 pages (26%) missing `og:title` and `twitter:title` entirely. |
| 7 | Proof hierarchy | **Unknown** | Requires runtime + manual review (Pass 3). |

**Weighted overall strategic clarity: ~32%**

Foundation (tree hygiene, build integrity) not assessed in this pass — deferred to Pass 2 build audit.

## Blocking Issues

### Blocking 1 — SEO Anti-Pattern Directories (Baseline dòng 86-91)

12 files in 6 untracked directories directly implement the anti-pattern baseline rejects:

```
website/en/youtube-downloader.html
website/en46/index.html
website/en46/privacy-policy.html
website/en80/index.html
website/en80/youtube-downloader.html
website/en81/facebook-downloader.html
website/en81/instagram-downloader.html
website/en81/tiktok-downloader.html
website/en81/twitter-downloader.html
website/en81/youtube-downloader.html
website/en81/youtube-to-mp3.html
website/en81/youtube-to-mp4.html
website/en81/linkedin-video-downloader.html
website/en81/privacy-policy.html
website/en82/9gag-downloader.html
website/en82/contact-us.html
website/en82/youtube-downloader.html
website/compare/vs-4k-downloader.html
website/compare/vs-online-converters.html
website/blog/download-tiktok-no-watermark.html
website/blog/download-youtube-playlist.html
website/blog/private-instagram-download.html
```

Baseline quote: "SEO-first copy repetition like `YouTube Downloader for PC` repeated across every layer" — listed as what NOT to copy from VidCombo.

**Remediation**: Each directory needs keep/delete/archive decision with written rationale. Recommended default: `git clean -fd` or move to `website/_archive/pre-baseline-2026-04-24/`. If kept, each file must be rewritten to baseline standards — which negates the SEO-farming purpose.

Landing CTO must decide; Verification CTO recommends delete.

### Blocking 2 — "Virus-free" Trust Badge on 32 Pages

Grep evidence from `website/index.html`:

```
<span class="trust-badge">
  <svg...><polyline.../></svg>
  Virus-free
</span>
```

Also on all locale download pages (`website/vi/download/macos.html`, `website/ar/download/windows.html`, etc.). Vietnamese copy: "không có virus".

Baseline rule 5 explicitly lists "virus-free" as a claim requiring extra scrutiny (line 197). The claim is not outright forbidden, but as a standalone badge it implies a scan guarantee SSvid cannot provide. Apple notarization ≠ malware scan in depth. Code-signing verifies identity of signer, not absence of malware.

**Remediation options** (Landing CTO decides):
1. **Replace with auditable claim**: "Code-signed by Apple Developer ID" or "Notarized by Apple" — both are true and verifiable via `codesign --verify`
2. **Remove the badge entirely**: Let the existing trust copy ("files stay on your device, no ads, no tracking") carry the load
3. **Keep but qualify**: "Apple-notarized, no known malware" — legal still risky

Verification CTO prefers option 1 or 2. Option 3 is legal/trust debt.

### Blocking 3 — "Best Video Downloader" Overclaim

2 pages:
- `website/guide.html`
- `website/compare/vs-4k-downloader.html` (anti-pattern dir — covered by Blocking 1)

Baseline line 275: "Generic 'best downloader' marketing language" listed as anti-pattern.

**Remediation**: Rewrite `guide.html` to avoid superlative claim. If `compare/` is deleted per Blocking 1, second page auto-resolves.

## Non-Blocking Observations

### W1 — Tree Hygiene

- 109 dirty files, 25 untracked directories
- 12 of 25 untracked dirs are **legitimate WIP**: `{ar,de,es,fr,hi,id,ja,ko,pt,ru,th,tr,vi,zh}/download/` — new locale download pages implementing Decision 4. DO NOT delete these.
- 6 of 25 are **SEO anti-pattern** (Blocking 1 above).
- 3 of 25 are **build output or unclear**: `website/css/`, `website/js/`, `website/scripts/` (1-2 files each). Should be covered by `.gitignore` or committed.
- 1 is `website/docs/` (my own verification docs + baseline).
- 3 miscellaneous (`website/blog/`, `website/compare/`, `website/en/`) — part of Blocking 1.

Recommendation: commit verification docs + baseline first (they're independent of landing work), then resolve SEO dirs, then chunk the 109 dirty source files by semantic batch (e.g. "locale download pages", "metadata updates", etc.).

### W2 — Platform Taxonomy Blended in All 15 Hero Pages

Every language homepage blends OS (macOS/Windows/Linux/iPhone/Android) with source platforms (YouTube/TikTok/Instagram/Facebook/X) in the same hero sentence. Violates Decision 2.

Marked as WARN in tool output but is effectively BLOCKING when Step 1 ("lock homepage message spine") begins. Flag now so Landing CTO sees it early.

### W3 — Social Metadata Missing on 29/111 Pages

26% of pages have no `og:title` and/or no `twitter:title`. Social share on those pages falls back to `<title>` or page URL. Inconsistent user experience across the site.

Should be fixed during Step 1 metadata lock.

### W4 — 14 Pages Missing Download CTA

Not the core legal pages (privacy/terms skipped by auditor). These are content pages without primary nav download link. Violates Decision 4 intent.

### W5 — Hero H1 Extraction Returned 0 Variants

Known audit tool bug — grep `<h1[^>]*>[^<]+</h1>` doesn't match multi-line or nested H1s. Will fix in Pass 2 (use proper HTML parser via node or python). For now, cannot verify H1 spine consistency from static audit.

### W6 — Tracker Guard Returned Clean

Current source has 0 references to `G-ZTHSEN0SZ3`, `googletagmanager.com`, or `gtag(` outside `dist/`. This is inconsistent with commit `6f04144e` log ("seo: add Google Analytics 4 tracking to all pages") — suggesting GA4 was added then removed in a subsequent pass, or lives in a linked external JS. Pass 2 build audit will resolve.

### W7 — Commit-Log vs Tree Divergence

Commit log mentions features (GA4, tier-SSS fixes, 12-issue sweep) that cannot be cleanly mapped to current tree state due to 109 uncommitted modifications. Audit is anchored to source, but Landing CTO's next request should list specific files modified per Step for targeted re-audit.

## Legitimate Work In Progress (Do Not Revert)

Credit where due — tree shows progress toward baseline:

- 12 new locale `*/download/` directories (4-locale sample checked: `vi`, `ar`, `ja`, `fr`) — implementing Decision 4 download-as-first-class-IA for i18n
- Verification tool docs exist (protocol + baseline + peer review) — institutional discipline layer
- No forbidden trackers in current tree (if commit log vs tree divergence is due to GA4 removal, that's a WIN)

These items shift Foundation score upward once committed + verified.

## Scorecard Divergence — Landing CTO (72%) vs Verification CTO (32%)

During this pass, Landing CTO produced a parallel scorecard at `website/docs/landing-scorecard-latest.md` (generated 07:39:56Z — 6 minutes before mine). Headline numbers:

| Metric | Landing CTO | Verification CTO | Delta |
|--------|------------:|-----------------:|------:|
| Overall | 72% | ~32% | 40 pts |
| Foundation | 69% | not scored | — |
| Strategic | 74% | ~32% | 42 pts |
| Decision 1 (Verb) | 100% | 40% | 60 |
| Decision 2 (Taxonomy) | 40% | 0% | 40 |
| Decision 3 (Hero) | 57% | 25% | 32 |
| Decision 4 (Download IA) | 83% | 50% | 33 |
| Decision 5 (Trust) | 60% | 20% | 40 |
| Decision 6 (Metadata) | 100% | 74% | 26 |
| Decision 7 (Proof) | 80% | Unknown | — |

Delta is large and must be reconciled before either score is trustworthy. The divergence is not a mistake — it is a methodological reality that confirms the necessity of two-agent verification.

### Cause 1 — Different audit surface

- Landing CTO audits `website/dist/` (current build output)
- Verification CTO audits `website/` **source** (what next build will emit)

Both surfaces matter for different reasons. Dist is what ships IF you deploy-as-is. Source is what ships IF you rebuild first. CI pipeline builds before deploy, so source is the operative surface for future deploys — but dist is the operative surface if emergency rsync deploy happens.

### Cause 2 — Source vs Dist Divergence (Standalone Finding)

Grep evidence:

- `virus-free` in **32 source pages** vs **17 dist pages** (source has 88% more violations than dist)
- `best video downloader` in 2 source pages AND 2 dist pages (no divergence)
- SEO anti-pattern dirs (`en46/en80/en81/en82/en/compare/blog/`) exist in **both** source (12 files) and dist (12+ files)

Interpretation: Landing CTO has been patching dist directly OR removing from source without rebuilding — which means rebuilding source emits MORE violations than currently in dist.

**This is its own finding and warrants a new blocking issue.** Tentative Blocking 4 — "Source-dist divergence on trust claims": rebuilding source today would ship 32 virus-free pages even though current dist has only 17. Rebuild-safety is broken.

### Cause 3 — Different forbidden-claim lists

Landing CTO forbidden list (inferred from scorecard evidence section):

- `best video downloader`
- `1000+ platform` claim
- `open-source engine`

Verification CTO forbidden list (explicit in `audit-static.sh`):

- `virus-free`, `100% safe`, `30x faster`, `NM+ users`, `fastest downloader`, `best video downloader`, `#1 downloader`, `no virus`, `malware-free`

Landing CTO's list aligns with baseline dòng 197-199 which says "virus-free" requires "extra scrutiny" — interpretable as WARN, not FAIL. Verification CTO interprets standalone trust badge as FAIL because a badge is stronger than body copy.

Neither list is wrong. Both need to converge before Step 1 completion. Recommendation: unified forbidden list in `website/docs/forbidden-claims.txt`, both scripts read from same source of truth.

### Cause 4 — Different H1 audit implementations

Landing CTO reports Decision 1 = 100% (4/4 checks passed). Verification CTO H1 extraction tool broke (known bug, W5). Landing CTO's implementation appears more robust. Verification CTO will adopt Landing CTO's approach in Pass 2 or cross-reference both.

### Cause 5 — Locale coverage

Landing CTO counts 56 localized pages separately, flags 71 taxonomy violations in locale. Verification CTO counts them inline with total 111 pages. Same universe, different slicing. Landing CTO's slicing is cleaner for locale debt tracking.

### Resolution Plan

For Pass 2:

1. Unify forbidden-claims list at `website/docs/forbidden-claims.txt`. Both scripts read from it.
2. Unify audit surface: define which surface is authoritative per check. Source for pre-commit checks; dist for pre-deploy checks. Expose `--surface source|dist` flag.
3. Adopt Landing CTO's H1 extraction implementation.
4. Produce a SINGLE reconciled scorecard at `website/docs/reconciled-scorecard.md` going forward, with both agents' contributions visible.
5. Add `Blocking 4 — Source-dist divergence` to this verdict (or resolve it by forcing a rebuild before re-audit).

Until reconciliation: both scorecards coexist, both must be cited in status reports, no single percentage should be quoted as "the score".

## Audit Tool Limitations (Pass 1 v1)

For Landing CTO's awareness — the following are known false negatives / gaps:

1. **H1 extraction** (Check D) misses multi-line or nested H1. Fix: use node/jsdom or python/BeautifulSoup in Pass 2.
2. **Hero section detection** (Check F) uses loose `awk` boundaries. Some hero mixing may go undetected, or non-hero sections may be flagged.
3. **4-things-only hero contract** (Decision 3) not auditable statically — requires semantic parsing. Deferred to Pass 3 runtime + manual review.
4. **Proof hierarchy** (Decision 7) not auditable statically — needs Pass 3.
5. **Trust claim context**: audit flags "virus-free" as keyword without parsing its surrounding trust context. In cases where claim is paired with "code-signed + notarized", auditor still flags as FAIL because standalone badge violates rule. Landing CTO may challenge specific instances.

## Risk-If-Deploy-Today (Brief)

If this tree were force-deployed today:

- **Legal/trust**: "Virus-free" badge is unsubstantiated standalone claim. Risk of consumer complaint or app store report. Severity: medium.
- **SEO**: 22 anti-pattern pages would ship as indexed canonical routes alongside real product pages → Google canonical dilution, potential manual action. Severity: medium-high.
- **Brand**: Hero on every homepage mixes OS+source — consistent but baseline-violating. Product message fuzzy. Severity: medium.
- **Conversion**: 14 pages without download CTA = dead ends for users at 12-13% of the site. Severity: low-medium.
- **Operational**: 109 dirty files means any emergency hotfix requires first resolving this queue. Severity: low.

Verdict on emergency deploy: possible but accumulates tech debt and trust debt in 3 dimensions. Recommend fixing Blocking 1-3 even in emergency mode.

## Recommendations to Landing CTO

Priority order for Step 1 (lock homepage message spine + metadata):

1. **Resolve SEO anti-pattern dirs first** (5 min decision, 1 min `git rm -r`). Blocks Step 1 and saves later confusion.
2. **Remove "Virus-free" badge from homepage + all 32 pages** during Step 1 metadata lock (it often co-locates with title area).
3. **Lock hero H1 to baseline formula** across all 15 homepages (English first, then translate).
4. **Separate OS row from source platform row** visually in hero — different row, different font weight, or different section.
5. **Add og/twitter meta to 29 missing pages** as part of metadata triple lock.
6. **Fix `guide.html`** superlative claim.

After these 6 items complete, submit verification request via `website/docs/verification-requests/step1-homepage-spine.md`.

## Next Verification Pass

Pass 2 focus (when Landing CTO requests):

- Fix audit-static.sh H1 extraction bug
- Implement `audit-build.sh` — run build, verify 111 output pages, sitemap, hreflang, sw.js version match
- Resolve commit-log vs tree divergence (where did GA4 go?)
- Re-score after Landing CTO Step 1 rework

Pass 3 focus (after Step 1 verdict PASS):

- Implement `audit-runtime.sh` — Playwright production-parity on built site
- A11y, LCP, keyboard nav, mobile viewport
- Hero contract semantic audit (Decision 3)
- Proof hierarchy verification (Decision 7)

## Artifacts

- Raw audit: `website/docs/verification-reports/2026-04-24-pass1-audit-static-raw.md`
- Audit script: `scripts/verify-landing/audit-static.sh`
- Baseline: `website/docs/landing-cto-baseline-2026-04-24.md`
- Peer review: `website/docs/landing-cto-peer-review-2026-04-24.md`
- Protocol: `website/docs/verification-protocol.md`

## Sign-off

Verification CTO — Pass 1 Baseline
2026-04-24T07:45Z

Status: **NO-GO**. Gate is red. Awaiting Landing CTO remediation + Step 1 submission.
