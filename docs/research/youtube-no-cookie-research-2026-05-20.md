# YouTube No-Cookie 403 — Decision Doc

**Status:** MEASURE-ONLY. No behavior change.  
**Owner:** Desktop CTO  
**Opened:** 2026-05-20  
**Closes when:** 48–72 h of production telemetry collected post-1.7.2 OR
the lab matrix below produces a reproducible recovery order.

---

## Why this doc exists

After 1.7.2 hardening (HEAD `09bb714d`), the single remaining HIGH-confidence
user-facing residual is YouTube `HTTP 403 / accessDenied` on the **no-cookie**
extraction path. Premium VidCombo users on Windows 10 build 26200 are the
recurring cluster (≈3–6 reports/week historically).

The cookie-present 403 path was fixed in commit `3da918cf` with typed
recovery. The no-cookie path is intentionally left untouched: any client
rotation guessed without evidence has historically *reduced* extraction
success rates (Google A/B-tests anti-abuse aggressively).

This doc is the holding pattern for the data we need before changing
behavior in 1.7.3.

---

## The two signal sources

### 1. Production telemetry (preferred — represents real users)

`ytdlp_datasource.dart` `_buildYouTubeExtractFailureMetadata` (line 1223)
already emits these fields per failed extract:

| Field | Why we need it |
|---|---|
| `is_youtube` | Filter to YouTube failures only |
| `has_youtube_cookies` | Split no-cookie vs cookie-present buckets |
| `cookie_source` | `none` / `file` / `browser:<name>` |
| `pot_provider_enabled` | Did we have POT provider attached? |
| `player_client` | Which client did yt-dlp try? |
| `deno_present` | Was Deno binary available for nsig? |
| `parsed_error_type` | Classifier verdict (rateLimited / accessDenied / …) |
| `looks_like_http_403` | Heuristic match on stderr |
| `stderr_excerpt` | First 500 chars of yt-dlp stderr |

**Query to run after 48 h:**

```
SELECT
  player_client,
  cookie_source,
  pot_provider_enabled,
  deno_present,
  parsed_error_type,
  COUNT(*) AS n
FROM download_errors
WHERE is_youtube = true
  AND has_youtube_cookies = false
  AND looks_like_http_403 = true
GROUP BY player_client, cookie_source, pot_provider_enabled,
         deno_present, parsed_error_type
ORDER BY n DESC;
```

Decision threshold: ≥ 50 failures across ≥ 5 distinct devices before
shipping a rotation policy.

### 2. Lab matrix (secondary — useful to disambiguate)

See `test/integration/youtube_no_cookie_lab.md` for the exact run sheet.
Lab data is **not authoritative** — residential IP reputation, CDN edge,
account state, and geo all influence Google's response. Lab confirms
*mechanism*; production confirms *prevalence*.

---

## Decision tree (filled in once data lands)

| Player client tried | Result on no-cookie | Notes |
|---|---|---|
| `default` (current) | TBD | baseline |
| `tv,mweb` (cookie-present pair) | TBD | parity test |
| `web_safari` | TBD | least-fingerprinted? |
| `android` | TBD | requires PO token? |
| `ios` | TBD | similar to android |
| `web_creator` | TBD | bypasses age gate sometimes |
| `mweb` only | TBD | lightest |

Once filled, the rotation order is the column with the lowest 403 rate
*conditioned on* `deno_present = true` AND `pot_provider_enabled = true`.
Below those preconditions, fix Deno/POT first — rotating clients without
them is treating a symptom.

---

## What is OUT of scope right now

- Changing the `--extractor-args youtube:player_client=...` argument
  for the no-cookie path.
- Adding a typed recovery branch for no-cookie 403.
- Adjusting POT provider fallback chain.
- Touching the cookie-present 3da918cf recovery (that one works).

All three are 1.7.3+ subjects, gated on the matrix above.

---

## Closure criteria

This doc converts to a 1.7.3 implementation spec when:

1. Production telemetry shows the dominant failure column with ≥ 50 events
   AND
2. Lab matrix corroborates the mechanism (or contradicts it loudly enough
   that we know not to ship a fix)
   AND
3. A draft typed recovery branch exists, mirroring `3da918cf` shape, with
   a regression test that locks the rotation order against future drift.

Until then: **standby. No code change to the no-cookie path.**
