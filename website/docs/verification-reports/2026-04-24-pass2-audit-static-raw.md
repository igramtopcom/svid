
# SSvid Landing — Static Audit

- Generated: 2026-04-24T08:05:04Z
- Commit: 5547cfa7
- Branch: main
- Scope: `website/` excluding `src/`, `docs/`, `_archive/`
- Total public HTML pages: 111

## A. Tree Hygiene

- Dirty files in `website/`: 116
- [WARN] Untracked directories present (need keep/delete/archive decision):
-   - `website/ar/download/` (3 files)
-   - `website/blog/` (3 files)
-   - `website/compare/` (2 files)
-   - `website/css/` (1 files)
-   - `website/de/download/` (3 files)
-   - `website/docs/` (12 files)
-   - `website/en/` (3 files)
-   - `website/en46/` (2 files)
-   - `website/en80/` (2 files)
-   - `website/en81/` (10 files)
-   - `website/en82/` (5 files)
-   - `website/es/download/` (3 files)
-   - `website/fr/download/` (3 files)
-   - `website/hi/download/` (3 files)
-   - `website/id/download/` (3 files)
-   - `website/ja/download/` (3 files)
-   - `website/js/` (1 files)
-   - `website/ko/download/` (3 files)
-   - `website/pt/download/` (3 files)
-   - `website/ru/download/` (3 files)
-   - `website/scripts/` (2 files)
-   - `website/th/download/` (3 files)
-   - `website/tr/download/` (3 files)
-   - `website/vi/download/` (3 files)
-   - `website/zh/download/` (3 files)
- [WARN] High dirty file count (116) — consider chunking commits

## B. Forbidden SEO Filename Patterns

- Baseline dòng 86-91 cấm 'YouTube Downloader for PC'-style SEO copy repetition.
- Pattern check: files như `*-downloader.html`, `vs-*.html`, `youtube-to-*.html`.
- [FAIL] SEO anti-pattern filenames detected:
-   - `website/en82/youtube-downloader.html`
-   - `website/en81/youtube-downloader.html`
-   - `website/en81/twitter-downloader.html`
-   - `website/en81/facebook-downloader.html`
-   - `website/en81/youtube-to-mp3.html`
-   - `website/en81/tiktok-downloader.html`
-   - `website/en81/instagram-downloader.html`
-   - `website/en81/youtube-to-mp4.html`
-   - `website/compare/vs-4k-downloader.html`
-   - `website/compare/vs-online-converters.html`
-   - `website/en80/youtube-downloader.html`
-   - `website/en/youtube-downloader.html`

## C. Forbidden Claims in Content

- Source of truth: `website/docs/forbidden-claims.txt` (shared with Landing CTO).
- [FAIL] Pattern `virus-free` in 32 page(s): matches forbidden pattern
-   - `website/vi/download/macos.html`
-   - `website/vi/download/windows.html`
-   - `website/index.html`
-   - ... (29 more)
- [FAIL] Pattern `fastest video downloader` in 26 page(s): matches forbidden pattern
-   - `website/index.html`
-   - `website/guide.html`
-   - `website/changelog.html`
-   - ... (23 more)
- [FAIL] Pattern `best video downloader` in 2 page(s): matches forbidden pattern
-   - `website/guide.html`
-   - `website/compare/vs-4k-downloader.html`

## D. Hero H1 Spine (Baseline Decision 1 + 3)

- Extractor: `lib/extract-metadata.py` — handles multi-line H1.
- Scope: homepage + locale index pages (e.g. `/vi/index.html`).
- Unique H1 variants across 16 home pages: **15**
- Per-locale H1 sample (first 5):
-   - [ar] احفظ أي فيديو. جودة أصلية. في ثوانٍ.
-   - [de] Jedes Video Speichern. Originalqualität. In Sekunden.
-   - [website/en/index.html] 
-   - [es] Guarda Cualquier Video. Calidad Original. En Segundos.
-   - [fr] Enregistrez N'importe Quelle Vidéo. Qualité Maximale. En Quelques Secondes.
- English canonical H1: `Save Any Video. Full Quality. On Your Device.`
- [PASS] 15 H1 variants (expected: 1 per locale = up to 15)

## E. Verb System Consistency — English Canonical (Baseline Decision 1)

- Rule: `Save` = outcome (hero/headline). `Download` = action (CTA/button).
- Scope: English pages only. Locale verb audit deferred to Pass 3 (requires per-locale Save translation map).
- EN H1 verb distribution across 2 English hero page(s):
-   - Save (outcome, correct): 1
-   - Download (action in H1, prefer CTA only): 0
-   - Keep (forbidden third framing): 0
-   - Get (third framing): 0
-   - Other: 1
- [PASS] No 'Keep' third-framing in English H1
- [FAIL] English H1 not on Save (1/2 use Save)

## F. Platform Taxonomy Separation (Baseline Decision 2)

- Rule: OS scope (macOS/Windows/Linux/iOS/Android) và source platforms (YouTube/TikTok/...) không được blend trong cùng sentence ở hero.
- [WARN] Hero mixes OS + source platforms in one sentence:
  - `website/ar/index.html`
  - `website/de/index.html`
  - `website/es/index.html`
  - `website/fr/index.html`
  - `website/hi/index.html`
  - `website/id/index.html`
  - `website/index.html`
  - `website/ja/index.html`
  - `website/ko/index.html`
  - `website/pt/index.html`
  - `website/ru/index.html`
  - `website/th/index.html`
  - `website/tr/index.html`
  - `website/vi/index.html`
  - `website/zh/index.html`
- Note: `1000+ platforms` phrase is allowed if OS support shown separately.

## G. Metadata Triple Consistency (Baseline Decision 6)

- Rule: `<title>`, `og:title`, `twitter:title` phải match (hoặc có exception ghi rõ).
- [PASS] All pages: `title`, `og:title`, `twitter:title` consistent (or one of og/tw missing)

## H. OG/Twitter Tag Presence

- [WARN] 29 / 111 pages missing `og:title`
- [WARN] 29 / 111 pages missing `twitter:title`

## I. Download CTA Presence (Baseline Decision 4)

- Rule: Download phải là first-class IA. Mọi public page nên có download link trong primary nav.
- [WARN] 14 page(s) missing download link in nav/body

## J. Tracker Regression Guard

- Site promises no-tracking. Check third-party analytics tags.
- [PASS] No tracker fingerprints detected

## K. Baseline Doc Integrity

- [PASS] Baseline doc present
- [PASS] Verification protocol present

## Summary

- Total public pages audited: 111
- Failures (blocking): **5**
- Warnings (non-blocking): **6**
- 
- **Verdict: STATIC FAIL** — resolve blocking issues before commit.
