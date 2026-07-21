# YouTube No-Cookie Lab — Run Sheet

**Purpose:** measure (NOT fix) the no-cookie 403 cluster. See companion
`docs/research/youtube-no-cookie-research-2026-05-20.md`.

## Environment

- Host: clean Windows 10 build 26200 VM (the production cluster). A macOS
  arm64 lab is acceptable as a control but NOT primary — Google's anti-
  abuse signal differs by OS user-agent.
- Network: residential IP via mobile hotspot is closest to user reality.
  Datacenter IP (CI runner) will distort the 403 rate downward.
- App: `scripts/dev.sh vidcombo release` — release-mode build, exactly
  what users run.
- Cookie state: profile MUST have no YouTube cookies. Verify with
  `BrowserCookieService.hasYouTubeCookies() == false`.
- Deno: present on PATH (`deno --version` ≥ 1.40).
- POT provider: enabled by default.

## URL bank (20 URLs)

Choose URLs that span:

| Bucket | URLs | Why |
|---|---|---|
| Public videos | 8 | baseline 403 rate |
| Geo-restricted (US-only) | 4 | known accessDenied class |
| Age-restricted public | 4 | known login-required class |
| Live archive | 2 | exotic codec path |
| Music label uploads | 2 | aggressive anti-abuse |

Pin the exact 20 URLs in `test/integration/youtube_no_cookie_urls.json`
before the first run so re-runs are comparable. **Do not change the bank
once a column is measured.** Recording the URLs in git protects the
historical comparison.

## Matrix

For each URL × player_client combination, capture:

| Column | Value |
|---|---|
| `player_client` | one of `default`, `tv,mweb`, `web_safari`, `android`, `ios`, `web_creator`, `mweb` |
| `extract_outcome` | `ok` / `403_no_cookie` / `pot_required` / `nsig_failed` / `other` |
| `formats_count` | length of `--dump-json` `formats[]` (storyboards-only = 1–2) |
| `audio_only_available` | bool |
| `1080p_available` | bool |
| `stderr_excerpt` | first 500 chars |

A **single row per (URL, player_client) pair.** Do not aggregate during
collection.

## Run protocol

```bash
# 1. Verify clean state
deno --version                          # ≥ 1.40
fvm flutter --version                   # 3.29.3
# Verify NO YouTube cookies in profile
sqlite3 ~/Library/Application\ Support/com.tinasoft.vidcombo/cookies.db \
  "select count(*) from cookies where host like '%youtube%';"
# expected: 0

# 2. Capture matrix (the harness will iterate URLs × clients)
fvm flutter test --no-pub test/integration/youtube_no_cookie_lab_test.dart \
  > test/integration/results-$(date +%Y%m%d-%H%M).log

# 3. Cool-off — 30 min between full passes (Google rate-limits per IP)

# 4. Repeat from a different residential IP at least once for validation
```

## What NOT to do

- **Do not** patch `ytdlp_datasource.dart` based on lab results alone.
  Production telemetry is authoritative. See the decision doc.
- **Do not** widen the URL bank mid-experiment.
- **Do not** mix cookie-present runs into this matrix — that path is
  already closed by `3da918cf`.
- **Do not** publish the URL bank — some are age-restricted and we don't
  want them dropping out of the bank because of takedowns.

## Output → research doc

Once a full matrix is in `test/integration/results-*.log`, paste the
aggregate counts into the **Decision tree** table in
`docs/research/youtube-no-cookie-research-2026-05-20.md` and update the
"Closure criteria" with a yes/no for each of the three conditions.

The lab harness `youtube_no_cookie_lab_test.dart` itself is intentionally
unimplemented in this commit — building it requires a real test VM with
network, Deno, and a clean cookie profile, which CI does not provide.
The harness is owned by whoever runs the lab.
