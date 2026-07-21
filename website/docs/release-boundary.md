# SSvid Website Release Boundary

Date: 2026-04-24
Owner: Landing CTO

## Purpose

This document defines the authoritative source, deploy surface, and the small set of legacy files that still ship with the SSvid landing site.

The goal is to prevent `website/` root from silently turning back into a second, stale website.

## Authoritative Source

These paths are the source of truth:

- `website/src/templates/`
- `website/src/css/`
- `website/src/js/`
- `website/src/i18n/`
- `website/src/assets/`
- `website/build.js`
- `website/package.json`
- `website/extract-translations.js`
- `website/version.json`
- `website/manifest.json`
- `website/site.webmanifest`
- `website/robots.txt`
- `website/CNAME`
- `website/_headers`
- `website/google*.html`
- `website/d13ff0a680a641a1a82fb5c927aea2d0.txt`

## Deploy Surface

Production is built from:

- `website/dist/`

GitHub Pages deploy flow:

1. `node website/build.js`
2. upload `website/dist/`
3. deploy that artifact

Anything outside `website/dist/` does not ship unless the builder copies it there.

## Allowed Legacy Source At Root

These root files still act as source because the builder copies them to `dist/`:

- `website/404.html`
- `website/launch.html`
- `website/launch.js`
- `website/payment/cancel.html`
- `website/payment/success.html`
- `website/payment/success.js`

These should be treated as legacy source, not as generated output mirrors.

## Explicitly Dead Surface

These categories must not be used as source of truth:

- root marketing HTML mirrors such as `website/index.html`, `website/pricing.html`, `website/privacy.html`
- locale root mirrors such as `website/fr/index.html`, `website/vi/index.html`
- root mirrors of migrated routes like `website/download/*.html`, `website/how-to/*.html`, `website/blog/*.html`, `website/compare/*.html`
- root asset mirrors duplicated from `website/src/assets/`
- root CSS/JS mirrors duplicated from `website/src/css/` and `website/src/js/`
- old legacy alias namespaces such as `website/en46/`, `website/en80/`, `website/en81/`, `website/en82/`

If these reappear, that is tree-hygiene debt, not deploy output.

## Boundary Rules

1. New public pages start in `website/src/templates/`, not in `website/` root.
2. New visual assets start in `website/src/assets/`, not in `website/` root.
3. `website/dist/` is the only deploy artifact.
4. Root legacy files are allowed only when the builder explicitly copies them.
5. Any future root mirror output should be removed instead of maintained in parallel.

## Operational Check

Before publish, verify:

- `npm run audit` passes
- `website/dist/launch.js` exists
- `website/dist/payment/success.js` exists
- no dead root mirror files were reintroduced
