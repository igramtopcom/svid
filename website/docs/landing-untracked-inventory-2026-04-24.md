# SSvid Landing Untracked Inventory

Date: 2026-04-24

Purpose: classify the current untracked `website/` paths so Phase 1 drift cleanup can proceed with explicit decisions instead of guesswork.

## Root-Level Inventory

| Path | Current role | Evidence | Recommended action |
|---|---|---|---|
| `blog/` | Intentional content track | `build.js` includes 3 blog pages and assigns sitemap priority for `blog/` routes | `KEEP (review content quality separately)` |
| `compare/` | Intentional comparison track | `build.js` includes 2 compare pages and assigns sitemap priority for `compare/` routes | `KEEP (review copy against baseline)` |
| `css/` | Generated asset directory | Build output now serves `/css/styles.css` and generated pages reference `/css/` | `KEEP` |
| `js/` | Generated asset directory | Build output now serves `/js/main.js` | `KEEP` |
| `docs/` | Landing operating docs | Baseline, peer review, scorecard, and policy lists live here | `KEEP` |
| `scripts/` | Measurement infra | `audit-landing.sh` and `audit-landing.mjs` now live here | `KEEP` |
| `en/` | Explicit English route namespace | `build.js` defines redirect handling for `en/index.html` and `en/terms-of-service.html` | `KEEP (but rationalize with locale policy)` |
| `en46/` | Legacy alias / variant namespace | `build.js` maps `en46/index.html` and `en46/privacy-policy.html` to canonical routes | `REVIEW -> likely ARCHIVE or redirect-only` |
| `en80/` | Legacy alias / variant namespace | `build.js` maps `en80/*` legacy pages to canonical routes | `REVIEW -> likely ARCHIVE or redirect-only` |
| `en81/` | Legacy alias / variant namespace | `build.js` maps `en81/*` legacy pages to canonical routes | `REVIEW -> likely ARCHIVE or redirect-only` |
| `en82/` | Legacy alias / variant namespace | `build.js` maps `en82/*` legacy pages to canonical routes | `REVIEW -> likely ARCHIVE or redirect-only` |

## Nested Untracked Paths

These paths appear intentional, not random debris:

- `ar/download/`, `de/download/`, `es/download/`, `fr/download/`, `hi/download/`, `id/download/`, `ja/download/`, `ko/download/`, `pt/download/`, `ru/download/`, `th/download/`, `tr/download/`, `vi/download/`, `zh/download/`
  Reason: the current builder generates localized OS-specific download pages.

These paths need explicit review because they can drift away from the new baseline:

- `hero-app*`, `hero-mobile-cards*`, `hero-replica.html`
  Reason: visual assets exist at root and can silently preserve older hero narratives.
- `guide.html`
  Reason: public utility route, but not yet included in the current strategic baseline.

## Immediate Cleanup Recommendation

Phase 1 should not delete untracked content blindly.

Recommended order:

1. Keep `docs/`, `scripts/`, `css/`, `js/`, locale `*/download/` outputs.
2. Decide whether `blog/` and `compare/` stay inside the acquisition system or become a separate SEO/content track.
3. Convert `en46/`, `en80/`, `en81/`, `en82/` from physical leftovers into documented redirect-only handling if possible.
4. Audit root visual assets and `guide.html` against the new baseline before deciding keep/delete/archive.

## Note

This inventory is not a final product decision. It is a cleanup control document so future passes can reference concrete classifications instead of treating all untracked paths as equal.
