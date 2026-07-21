# YouTube 403 Lab Runbook — `9xB8oXx4PXs` and beyond

**Status:** MEASURE-ONLY. No production behavior change.
**Owner:** Desktop CTO + tester ops
**Opened:** 2026-05-21
**Pairs with:** `docs/research/youtube-no-cookie-research-2026-05-20.md`
**Closes when:** matrix of ≥ 50 events / column has been collected
across ≥ 5 distinct residential IPs on Windows + macOS, and a
recommended `player_client` / POT policy is recorded with evidence.

---

## Why this runbook exists

Production log `log.md` 2026-05-21 Incident A shows a Windows
tester's YouTube downloads failing in a deterministic loop:

```
[YtDlp] YouTube download failed: exit=1 ytDlp=2026.03.17
  pot=true player_client=tv,mweb cookies=true
  format=bestvideo[height<=1080]+bestaudio
  error=ERROR: unable to download video data: HTTP Error 403: Forbidden

[yt-dlp] Download cookieDbLocked — retrying with cookies-from-browser=firefox (chain 2/4).
[yt-dlp] Download failed with accessDenied + cookies present. Cookies may be bad/expired — retrying WITHOUT cookies once.
```

The chain exhausts all 4 cookies-from-browser fallbacks AND a
no-cookies retry, all hitting HTTP 403 on the media-stream URL.
Chairman + Codex Decision Package 2026-05-21: do NOT blind-rotate
`player_client` in production. Run a measure-only lab matrix first
to identify which (player_client, POT, cookie state) combination
recovers, then ship a surgical fix in a 1.7.3 follow-up commit.

This runbook is the protocol for that lab work.

---

## Test URL bank

| ID | URL | Why |
|---|---|---|
| `9xB8oXx4PXs` | `https://www.youtube.com/watch?v=9xB8oXx4PXs` | The Windows tester's reproducer from `log.md` Incident A — primary target |
| `dQw4w9WgXcQ` | classic Rick Astley | Standard public baseline; if this fails too, the issue is the test environment |
| `kJQP7kiw5Fk` | Despacito | High-popularity, age-unrestricted, baseline 2nd |
| `5qap5aO4i9A` | lofi hip hop livestream | DASH-only, no progressive; tests merge path |
| `KK9bwTlAvgo` | recent music video (≥ 1440p) | Hits Opus-forced height; tests `MP4 → recode` path landed in commit 43a6701a |

Add 5–10 more URLs across categories (age-restricted, members-only,
short-form, live archive) when populating the matrix.

---

## Environment matrix

| Var | Values |
|---|---|
| OS | Windows 10 26200, macOS arm64 |
| Network | residential IP (mobile hotspot), datacenter IP (CI runner) |
| Browser running | none, Chrome only, Edge only, Firefox only |
| In-app cookie state | absent, fresh (just signed in), stale (24 h old) |
| `player_client` | `default`, `tv,mweb`, `web_safari`, `android`, `ios`, `web_creator`, `mweb` |
| POT provider | enabled, disabled |
| Deno binary | present, missing |

A single full sweep = 5 URLs × 7 player_clients × 2 POT × 4
in-app-cookie states = **280 cells per OS**. Realistic first pass:
5 URLs × 4 player_clients × 2 POT × 2 cookie states = 80 cells per
OS. Cool down 30 min between bursts to avoid IP-level rate limits.

---

## How to capture per cell

For each (URL, player_client, POT, cookie_state) cell, record:

1. yt-dlp exit code
2. `error=...` line from yt-dlp stderr (truncated to 500 chars)
3. Final on-disk filename (if any)
4. Time-to-failure or time-to-completion
5. Whether `[jsc:deno] Solving JS challenges using deno` appeared
6. Whether yt-dlp reported `Sign in to confirm you're not a bot`
7. `looks_like_http_403` boolean (the heuristic from
   `ytdlp_datasource.dart:1192`)

Write the row to a single CSV at
`docs/research/yt-403-lab-results-<host>-<YYYYMMDD>.csv` so post-hoc
filtering is trivial.

---

## How to drive the matrix (manual + scripted)

There is no automated production-runner for this. Until we ship a
proper integration harness (deferred; CI cannot supply a residential
IP or a clean cookie profile), drive the matrix manually via either:

**Path A — through the production app** (signal-rich, slow):
  1. `scripts/dev.sh svid release` (build the same artifact users
     run).
  2. Use Settings → yt-dlp Engine to flip player_client / POT.
  3. Capture stderr from the application log file.

**Path B — direct yt-dlp CLI** (faster, less app-coupled):

```bash
DENO=$(which deno)
YTDLP=~/.local/share/com.svid.app/binaries/yt-dlp
COOKIES=~/.local/share/com.svid.app/cookies/youtube.txt

for PLAYER_CLIENT in default tv,mweb web_safari android ios; do
  for POT in true false; do
    for COOKIES_FLAG in "--cookies $COOKIES" ""; do
      $YTDLP \
        --js-runtimes "deno:$DENO" \
        --extractor-args "youtube:player_client=$PLAYER_CLIENT" \
        ${POT:+--extractor-args youtube:pot_provider=auto} \
        $COOKIES_FLAG \
        -f 'bestvideo[height<=1080]+bestaudio' \
        --skip-download \
        --print 'after_move:filepath' \
        "https://www.youtube.com/watch?v=9xB8oXx4PXs"
      echo "exit=$? player=$PLAYER_CLIENT pot=$POT cookies=$COOKIES_FLAG"
    done
  done
done > lab-9xB8oXx4PXs-$(hostname)-$(date +%Y%m%d).csv 2>&1
```

The script above does NOT touch production code. Tweak args per
your local binary paths.

---

## Decision rule once data lands

Define a "winner" cell = exit 0 AND no `looks_like_http_403` AND
the merged file existed at the printed final path.

A `player_client` value is RECOMMENDED for production ROUT only when:

1. It wins ≥ 70 % of cells where (POT=true, cookies=present) on
   Windows AND
2. It does not REGRESS the macOS happy path (i.e. it still wins on
   Mac under cookies=present)

Anything below threshold goes back into the lab — no blind
production rotation.

---

## What this runbook is NOT

- It is not a recipe for "rotate player_client randomly in
  production until something works". That path was tried by
  predecessors and degrades the success rate; it cannot ship.
- It is not a substitute for production telemetry. The telemetry
  schema landed in commit `e47de4f5` is what catches the
  long-tail variants the lab won't enumerate. The lab finds the
  fix; telemetry confirms it scaled.
- It is not blocking the current branch's other production work.
  Facebook (C1/C2) and cookie-precedence (C3/C4) ship on their
  own.
