# Android In-App Update — Backend Integration (ssvid + vidcombo)

**Scope:** Contract between the Android clients (ssvid + vidcombo, `ssvid-android` repo) and **this Go backend** (`snakeloader/backend`).
**Last updated:** 2026-06-01

**Status:**
- ✅ Android client DONE (compiled + runtime-verified on device).
- ✅ **Backend now accepts `android`** — enabled 2026-06-01 in this repo (`app_release_dto.go:11`, `ci_release_handler.go:44`). The check endpoint already accepted it (see "Validation reality" below).
- ⏳ Remaining for end-to-end: register a per-brand, signed `.apk` release (direct `download_url` + SHA-256). Until a release row exists, the check correctly returns `update_available:false`.

## Why this doc

The Android apps (ssvid + vidcombo) previously checked for updates against two
team-external PHP endpoints:
- `https://api.ssvid.app/app_version.php` → **HTTP 404** (route dead)
- `https://api.vidcombo.com/app_version.php` → 200 but missing `apk_url`

The Android in-app updater was migrated to consume **this Go backend's
`/api/v1/updates/check`** — the same endpoint desktop snakeloader already uses —
so one backend serves desktop + Android with one schema.

## What the Android client sends (matches `product_handler.go:86-114`)

```
GET /api/v1/updates/check?platform=android&version={versionName}&channel=stable&brand={ssvid|vidcombo}
```

- `platform=android`
- `version` — e.g. `1.6.0` (Android `BuildConfig.VERSION_NAME`). Matches the
  handler's `c.Query("version")` — NOT `current_version`. (The older
  `docs/FLUTTER_INTEGRATION_GUIDE.md` says `current_version`, which is stale and
  does not match the current handler.)
- `channel=stable`
- `brand=ssvid` or `brand=vidcombo` — sent explicitly by Android.

### Base URL — BOTH brands use the single Go host (mirror desktop)

This is the source-of-truth model the desktop app already runs:

| Brand    | Update-check base URL (Go)                  |
|----------|---------------------------------------------|
| ssvid    | `https://api.ssvid.app/api/v1/updates/check` |
| vidcombo | `https://api.ssvid.app/api/v1/updates/check?brand=vidcombo` |

The Go backend lives **only at `api.ssvid.app`**. Brands are differentiated by the
`?brand=` query param, not by host — exactly how desktop does it
(`brand_config.dart` → `goBackendBaseUrl` is `api.ssvid.app/api/v1` for *both*
brands). `api.vidcombo.net` is the **PHP** host (checkkey.php / version.php); it
does **not** serve this Go route.

> ⚠️ **Android-repo action required:** the vidcombo flavor's `UPDATE_API_URL`
> must point to `https://api.ssvid.app/api/v1/updates/check` (with
> `brand=vidcombo`), **not** `https://api.vidcombo.net/...`. Pointing it at the
> PHP host will 404. (This is a change in `ssvid-android` `app/build.gradle`,
> outside this backend repo.)

## Validation reality (corrects an earlier version of this doc)

An earlier draft claimed the check endpoint hard-blocks `android` via
`CheckUpdateRequest.Platform binding:"oneof=macos windows linux"`. **That was
incorrect:**

- The `CheckUpdate` handler (`product_handler.go:86-114`) reads `c.Query("platform")`
  **directly** — it does not `ShouldBind` any struct. It only rejects an *empty*
  platform/version.
- `CheckUpdateRequest` (`app_release_dto.go:33`) is **unused dead code** (no
  reference anywhere in the repo). Its `oneof` never executes.

→ `platform=android` was **always accepted** on the check path. The
runtime-verified `update_available:false` ("Latest version: null") came from
*no android release being registered* (`FindPublished("android", …)` returns 0
rows) — not from validation.

The platform whitelist that actually mattered was on the **registration** paths,
now updated to include `android`:

| Enforcement point | File | Status |
|---|---|---|
| Admin register `POST /admin/v1/releases` (binds `CreateAppReleaseRequest`) | `app_release_dto.go:11` | ✅ `android` added |
| CI register `POST /internal/ci/releases` (hardcoded map) | `ci_release_handler.go:44` | ✅ `android` added |
| Check `GET /api/v1/updates/check` | `product_handler.go:87` | already permissive (reads query) |
| DB model `AppRelease.Platform` | `app_release.go` | `size:50`, no CHECK constraint — accepts any string (no migration needed) |

Note: `CheckUpdateRequest` remains as-is (dead code, harmless); a future cleanup
may remove it.

## Response schema (already correct — no change needed)

The Android client parses **exactly** `UpdateCheckResponse`
(`app_release_dto.go:75-85`) inside the standard `{success, data}` envelope —
identical to the desktop `UpdateCheckResponse` (`backend_dtos.dart:445-479`):

```json
{
  "success": true,
  "data": {
    "update_available": true,
    "latest_version": "1.6.0",
    "current_version": "1.5.0",
    "is_mandatory": false,
    "release_notes": "…",
    "download_url": "https://…/ssvid-1.6.0.apk",
    "file_size": 50401069,
    "checksum": "<sha256 hex>",
    "published_at": "2026-06-01T…Z"
  }
}
```

## Operational requirements to ship an Android update end-to-end

These are not code blockers (backend already accepts android); they are what a
registered Android release row must satisfy:

1. **`download_url` MUST be a direct `.apk` file.** Android's `DownloadManager`
   fetches it and hands it to the package installer; a redirect to an HTML
   landing page installs nothing. Host the APK as a direct asset (e.g. GitHub
   release asset / CDN), mirroring how desktop distributes via `ssvid-releases`.
2. **Per-brand, correctly-signed APK.** ssvid APK signed with the SSVID release
   key, vidcombo with its own. Serving the wrong brand's APK (or a debug-signed
   one) to an installed app fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
   Each brand's release row points to its own signed APK.
3. **`checksum` = SHA-256 of the APK (recommended).** When present, the Android
   client verifies the downloaded APK's SHA-256 and **refuses to install on
   mismatch**. If omitted, the download installs unverified — always send it.

## ⚠️ LANDMINE: Android version-lines differ per brand AND from desktop

Each (platform, brand, channel) is an independent version bucket. The Android
version-lines are **not** the desktop ones:

| App | version-line (as of 2026-06-01) | Source |
|-----|---------------------------------|--------|
| ssvid-android    | `1.6.0` | `app/build.gradle:58` |
| vidcombo-android | `5.0.0` | `app/build.gradle:116` |
| ssvid-desktop    | `1.3.x` | (different bucket) |
| vidcombo-desktop | `1.7.x` | (different bucket) |

When registering an **android** release you MUST use that brand's android
version-line:
- `brand=vidcombo, platform=android` → version must be **≥ 5.x** (NOT 1.7.x from
  desktop vidcombo).
- `brand=ssvid, platform=android` → version must be **> 1.6.0**.

If you register an android release with a desktop-style version (e.g. vidcombo
android `1.7.0`), BOTH the backend comparison AND the Android client's local
safety-net (`isNewerVersion`, `UpdateManager.kt`) will treat it as "no update" —
the update silently never ships. Always match the android brand's own line.

## Verification once a release is registered

1. Register a test Android release (version higher than installed) for brand `ssvid`
   (admin `POST /admin/v1/releases` with `platform=android`, or CI
   `POST /internal/ci/releases` with an `android` key in `platforms`).
2. `GET /api/v1/updates/check?platform=android&version=1.5.0&channel=stable&brand=ssvid`
   → expect `update_available:true` with a direct `.apk` `download_url` + `checksum`.
3. Repeat with `brand=vidcombo` (same host, `?brand=vidcombo`).

## Android client reference (ssvid-android repo)

- `update/UpdateInfo.kt` — `UpdateResponse` envelope + `UpdateInfo` (mirrors `UpdateCheckResponse`)
- `update/UpdateManager.kt` — check, download, SHA-256 verify, state machine
- `update/UpdateDialogFragment.kt` — dialog, mandatory handling, install intent
- `update/DownloadState.kt` — Idle / Downloading / Verifying / Success / Failure
- `brand/BuildConfigUpdateGateway.java` — builds the query
- `app/build.gradle` — `UPDATE_API_URL` per flavor (vidcombo must point to `api.ssvid.app`)
- Full Android-side contract: ssvid-android `docs/ANDROID_UPDATE_CONTRACT.md`
