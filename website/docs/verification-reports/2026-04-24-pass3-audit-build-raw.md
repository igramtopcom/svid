
# SSvid Landing — Build Audit

- Generated: 2026-04-24T08:14:31Z
- Commit: 3f748b85
- Scope: `website/dist/` + source-dist divergence

## A. Dist Presence & Freshness

- Dist HTML page count: 112
- [PASS] Dist is fresh (2 min old)
- Source HTML page count: 111
- [WARN] Dist has 1 more pages than source — possible orphan output

## B. Source-Dist Divergence on Forbidden Claims

- Purpose: detect cases where source has more violations than dist (rebuild-safety risk).

| Pattern | Source | Dist | Divergence | Severity |
|---------|-------:|-----:|-----------:|:---------|
| `virus-free` | 32 | 0 | +32 | FAIL |
| `2M+ users` | 0 | 0 | +0 | FAIL |
| `30x faster` | 0 | 0 | +0 | FAIL |
| `fastest video downloader` | 26 | 0 | +26 | FAIL |
| `best video downloader` | 2 | 0 | +2 | FAIL |
| `100% safe` | 0 | 0 | +0 | FAIL |
| `everything syncs automatically` | 0 | 0 | +0 | FAIL |
| `cross-platform sync` | 0 | 0 | +0 | FAIL |

- [FAIL] 3 FAIL-severity pattern(s) have more violations in source than dist — rebuild would ship MORE violations than currently in dist

## C. Sitemap Validity

- Sitemap path: `website/dist/sitemap.xml`
- [PASS] Sitemap is valid XML
- Sitemap URL entries: 81
- [PASS] Sitemap URL count within expected range

## D. Service Worker Cache Version

- [WARN] Cannot extract version from sw.js — manual review needed

## E. Critical Asset Presence in Dist

- [PASS] `index.html` present
- [PASS] `robots.txt` present
- [PASS] `sitemap.xml` present
- [PASS] `site.webmanifest` present
- [PASS] `sw.js` present
- [PASS] og:image asset present

## F. hreflang Coverage

- Hreflang tags on homepage: 16
- [PASS] Hreflang coverage >= 15 (all locales)

## Summary

- Failures (blocking): **1**
- Warnings (non-blocking): **2**

**Verdict: BUILD FAIL** — resolve blocking issues before commit/deploy.
