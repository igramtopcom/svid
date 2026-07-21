#!/usr/bin/env bash
# =============================================================================
# Pre-release validation — runs the gates that v1.3.6 / v1.6.3 missed.
#
# Existing `verify_release_gates.sh` covers analyze / signing / brand-assets
# / cargo. This script covers the production-reality gates that compile-time
# correctness alone doesn't catch:
#
#   1. Workflow YAML symmetry — every upload-artifact pattern in build-*
#      jobs has a matching download-artifact in the release-creation job.
#      The v1.3.6 / v1.6.3 release silently shipped without Linux artifacts
#      because the release job downloaded only `*-macOS` and `*-Windows`,
#      not `*-Linux` (release.yml:605-611). Linux had zero users so the
#      hit was small, but the same pattern would silently drop any future
#      platform addition.
#
#   2. External binary URL liveness — every URL in lib/core/binaries/
#      binary_info.dart (primary + fallbacks) HEAD-checks to a real 200
#      response, with redirects followed. Catches the upstream-publishes-
#      empty-release pattern (mikf/gallery-dl v1.32.0 on 2026-04-24
#      shipped with zero assets, which silently bricked Windows fresh
#      installs of VidCombo until users blew through the install flow).
#
#   3. Backend release-record health — every brand × platform release
#      record on api.svid.app `/admin/v1/releases` for the version about
#      to ship has `is_active=true` AND `published_at` non-null. The
#      v1.3.6 dispatch went out with NULL `published_at` on every record
#      (admin POST default), so the public `/api/v1/updates/check`
#      filter (`WHERE published_at IS NOT NULL`) returned the OLD
#      version for 2 days until em manually PATCHed.
#
# Run BEFORE tagging:
#
#   bash scripts/preflight_release.sh
#
# Optional environment for Gate 3 (backend record check):
#
#   PREFLIGHT_VERSION_SVID=1.3.7   PREFLIGHT_VERSION_VIDCOMBO=1.6.4
#   ADMIN_EMAIL=admin@svid.app     ADMIN_PASSWORD="${ADMIN_PASSWORD}"
#
# Returns non-zero if ANY gate fails so it can wire into a pre-tag hook.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Default: WARN → exit 1 ("not safe to tag" is the literal message).
# A previous default of exit-0-on-warn meant any automation that only
# checks `$?` treated a warned run as success — review feedback round 4
# called this out as a real CI gap.
#
# --allow-warnings: opt-in escape hatch. Use when warnings are explicitly
#   acceptable (e.g. fallback URLs that mirror an upstream-empty release
#   you've deliberately accepted). Logged loud so reviewer can see it
#   was a conscious override, not a missed signal.
# --strict: kept for backward compat, behaves identically to default now.
ALLOW_WARNINGS=0
EXPECTED_PLATFORMS="macos windows"  # `linux` deliberately omitted —
                                     # 0 Linux devices in fleet per
                                     # 2026-04-27 audit. Override via
                                     # PREFLIGHT_PLATFORMS env if Linux
                                     # adoption changes.
for arg in "$@"; do
  case "$arg" in
    --allow-warnings) ALLOW_WARNINGS=1 ;;
    --strict) ALLOW_WARNINGS=0 ;;  # backward-compat, same as default
    --help|-h)
      cat <<'USAGE'
Usage: bash scripts/preflight_release.sh [--allow-warnings|--strict]

Default: every WARN gate makes the script exit non-zero so the message
"not safe to tag" cannot be ignored by an exit-code-only check.

Environment:
  ADMIN_EMAIL, ADMIN_PASSWORD              Admin login for Gate 3
  PREFLIGHT_VERSION_SVID                  e.g. 1.3.7
  PREFLIGHT_VERSION_VIDCOMBO               e.g. 1.6.4
  PREFLIGHT_PLATFORMS                      space-separated, default
                                           "macos windows" (linux
                                           skipped — 0 fleet devices)

Flags:
  --allow-warnings   Treat WARN as advisory. Use only when warnings are
                     explicitly acceptable (e.g. known-broken upstream
                     fallback URL). Override is logged loudly.
  --strict           Backward-compat alias for default behaviour (WARN
                     blocks the gate). Kept so existing callers still
                     work.
USAGE
      exit 0
      ;;
  esac
done

# Allow env override of expected platform list.
if [ -n "${PREFLIGHT_PLATFORMS:-}" ]; then
  EXPECTED_PLATFORMS="$PREFLIGHT_PLATFORMS"
fi

declare -a RESULTS=()
record() {
  local id="$1" status="$2" detail="${3:-}"
  RESULTS+=("${status}|${id}|${detail}")
  local color
  case "$status" in
    PASS) color='\033[0;32m' ;;
    FAIL) color='\033[0;31m' ;;
    WARN) color='\033[0;33m' ;;
    SKIP) color='\033[0;90m' ;;
    *)    color='' ;;
  esac
  printf '%b[%s]%b %s' "$color" "$status" '\033[0m' "$id"
  [ -n "$detail" ] && printf ' — %s' "$detail"
  printf '\n'
}

# -----------------------------------------------------------------------------
# Gate 1 — Workflow YAML symmetry.
#
# Every artifact name uploaded by a build-* job must appear in a
# download-artifact step inside the release-creating job. A pattern
# defined in upload-artifact `name:` should match a download-artifact
# `pattern:` glob in the same workflow.
# -----------------------------------------------------------------------------
echo
echo "== Gate 1 — Workflow artifact symmetry =="

WORKFLOW=".github/workflows/release.yml"
if [ ! -f "$WORKFLOW" ]; then
  record G1.workflow SKIP "no $WORKFLOW found"
else
  # Pull every artifact name uploaded — line above `path:` in upload-artifact
  # blocks. Names contain ${{ matrix.brand }} placeholders we treat as glob.
  uploaded=$(awk '
    /uses: actions\/upload-artifact/ { in_upload=1; next }
    in_upload && /name:/ {
      gsub(/^[[:space:]]+name:[[:space:]]+/, "");
      gsub(/\$\{\{[^}]+\}\}/, "*");
      print;
      in_upload=0;
    }
  ' "$WORKFLOW" | sort -u)

  # Pull every download-artifact pattern. Same placeholder treatment.
  downloaded=$(awk '
    /uses: actions\/download-artifact/ { in_dl=1; next }
    in_dl && /pattern:/ {
      gsub(/^[[:space:]]+pattern:[[:space:]]+/, "");
      gsub(/['\''"]/, "");
      print;
      in_dl=0;
    }
  ' "$WORKFLOW" | sort -u)

  missing=""
  while IFS= read -r up; do
    [ -z "$up" ] && continue
    # Normalize: strip quotes
    up_norm=$(echo "$up" | tr -d "'\"")
    matched=0
    while IFS= read -r dl; do
      [ -z "$dl" ] && continue
      # Glob match: case "$up" in $dl) — but bash extglob unreliable here.
      # Use literal contains: every download pattern is a substring of the
      # normalized upload (e.g. download "*-Linux" matches upload "*-Linux").
      stripped="${dl//\*/}"
      case "$up_norm" in
        *"$stripped"*) matched=1; break ;;
      esac
    done <<< "$downloaded"
    if [ "$matched" = "0" ]; then
      missing="${missing}${up_norm}\n"
    fi
  done <<< "$uploaded"

  if [ -n "$missing" ]; then
    record G1.workflow FAIL "upload-artifact name(s) without matching download-artifact pattern"
    printf '%b' "$missing" | sed 's/^/    /' | head -10
  else
    record G1.workflow PASS "every upload has a matching download"
  fi
fi

# -----------------------------------------------------------------------------
# Gate 2 — External binary URL liveness.
#
# Every URL declared in lib/core/binaries/binary_info.dart (primary
# downloadUrl + every fallbackUrls entry) must resolve to a 200 after
# following redirects. Skipped when curl is unavailable (rare).
# -----------------------------------------------------------------------------
echo
echo "== Gate 2 — Binary URL liveness =="

if ! command -v curl >/dev/null 2>&1; then
  record G2.urls SKIP "curl not available"
else
  # Parse binary_info.dart with state-aware awk: track whether the
  # current line is inside a `fallbackUrls: [ ... ]` block. Lines inside
  # = fallback URLs (WARN on 404, defense-in-depth). Lines outside =
  # primary (FAIL on 404). URLs with `$` are runtime-substituted
  # placeholders (e.g. martin-riedl.de `$arch`) — skipped.
  parsed=$(awk '
    /fallbackUrls:/ { in_fb=1 }
    {
      # Extract every https URL on the line.
      s = $0
      while (match(s, /https:\/\/[^"'\''[:space:]]+/)) {
        url = substr(s, RSTART, RLENGTH)
        if (index(url, "$") == 0) {
          if (in_fb) print "FALLBACK\t" url
          else print "PRIMARY\t" url
        }
        s = substr(s, RSTART + RLENGTH)
      }
    }
    in_fb && /\]/ { in_fb=0 }
  ' lib/core/binaries/binary_info.dart 2>/dev/null)

  primary_urls=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="PRIMARY"{print $2}' | sort -u)
  fallback_urls=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="FALLBACK"{print $2}' | sort -u)

  primary_failed=""
  primary_total=0
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    primary_total=$((primary_total + 1))
    code=$(curl -sIL --max-time 15 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
    if [ "$code" = "200" ]; then
      echo "    [200] (primary) $url"
    else
      echo "    [$code] (primary) $url"
      primary_failed="${primary_failed}${code} ${url}\n"
    fi
  done <<< "$primary_urls"

  fallback_failed=""
  fallback_total=0
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    fallback_total=$((fallback_total + 1))
    code=$(curl -sIL --max-time 15 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
    if [ "$code" = "200" ]; then
      echo "    [200] (fallback) $url"
    else
      echo "    [$code] (fallback) $url"
      fallback_failed="${fallback_failed}${code} ${url}\n"
    fi
  done <<< "$fallback_urls"

  if [ -n "$primary_failed" ]; then
    record G2.urls FAIL "$(printf '%b' "$primary_failed" | grep -c '^[0-9]') primary URL(s) non-200"
    printf '%b' "$primary_failed" | sed 's/^/    PRIMARY-FAIL /'
  elif [ -n "$fallback_failed" ]; then
    record G2.urls WARN "$(printf '%b' "$fallback_failed" | grep -c '^[0-9]') fallback URL(s) non-200 (defense-in-depth degraded; primary still works)"
  else
    record G2.urls PASS "$((primary_total + fallback_total)) URL(s) all 200"
  fi
fi

# -----------------------------------------------------------------------------
# Gate 3 — Backend release-record health.
#
# After ship + manual register, the public /api/v1/updates/check endpoint
# returns latest_version=<new> only when the record has `published_at`
# non-null AND is_active=true. We hit the admin endpoint and assert both.
# Skipped when admin credentials are not provided (don't store secrets in
# CI envvars by default).
# -----------------------------------------------------------------------------
echo
echo "== Gate 3 — Backend release records =="

ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
PREFLIGHT_VERSION_SVID="${PREFLIGHT_VERSION_SVID:-}"
PREFLIGHT_VERSION_VIDCOMBO="${PREFLIGHT_VERSION_VIDCOMBO:-}"

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  record G3.records SKIP "ADMIN_EMAIL / ADMIN_PASSWORD not set"
elif [ -z "$PREFLIGHT_VERSION_SVID$PREFLIGHT_VERSION_VIDCOMBO" ]; then
  record G3.records SKIP "PREFLIGHT_VERSION_SVID / _VIDCOMBO not set (run after ship)"
elif ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  record G3.records SKIP "curl or python3 missing"
else
  TOKEN=$(curl -s --max-time 30 -X POST "https://api.svid.app/admin/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('token',''))" 2>/dev/null)

  if [ -z "$TOKEN" ]; then
    record G3.records FAIL "admin login failed"
  else
    issues=""
    no_records=""
    for spec in "svid:$PREFLIGHT_VERSION_SVID" "vidcombo:$PREFLIGHT_VERSION_VIDCOMBO"; do
      brand="${spec%%:*}"
      version="${spec##*:}"
      [ -z "$version" ] && continue

      # Walk every page of /admin/v1/releases until we find target
      # records or exhaust the table. Backend caps at 100 per page;
      # release history can exceed that as the product matures, so a
      # one-shot fetch silently false-fails this gate when the target
      # version is older than the most recent 100 records (review
      # feedback round 2). We stream pages into a temp file because
      # bash here-strings choke on multi-MB JSON.
      tmp_releases=$(mktemp)
      printf '[]' > "$tmp_releases"
      page=1
      while :; do
        page_resp=$(curl -s --max-time 30 \
          "https://api.svid.app/admin/v1/releases?page=$page&per_page=100" \
          -H "Authorization: Bearer $TOKEN")
        # Append items to the accumulator and decide whether to keep
        # paging based on whether this page returned a full 100.
        more=$(printf '%s' "$page_resp" | TMP_ACCUM="$tmp_releases" python3 -c "
import json, os, sys
resp = json.load(sys.stdin)
items = resp.get('data', {}).get('items', [])
total_pages = resp.get('data', {}).get('total_pages', 1)
current_page = resp.get('data', {}).get('page', 1)
acc_path = os.environ['TMP_ACCUM']
with open(acc_path, 'r+') as f:
    accum = json.load(f)
    accum.extend(items)
    f.seek(0)
    f.truncate()
    json.dump(accum, f)
print('1' if current_page < total_pages else '0')
" 2>/dev/null)
        [ "$more" = "1" ] || break
        page=$((page + 1))
        # Safety cap — production should never have >50 pages of
        # releases (5000 records). If we hit this, something is wrong.
        if [ "$page" -gt 50 ]; then
          break
        fi
      done

      result=$(EXPECTED_PLATS="$EXPECTED_PLATFORMS" \
        TARGET_BRAND="$brand" TARGET_VERSION="$version" \
        TMP_ACCUM="$tmp_releases" \
        python3 -c "
import json, os, sys
items = json.load(open(os.environ['TMP_ACCUM']))
brand = os.environ['TARGET_BRAND']
version = os.environ['TARGET_VERSION']
target = [r for r in items if r.get('brand')==brand and r.get('version')==version]
if not target:
    print('NO_RECORDS')
    sys.exit()

expected = set(os.environ.get('EXPECTED_PLATS','macos windows').split())
got = {r.get('platform') for r in target}
missing = sorted(expected - got)
if missing:
    print(f\"MISSING_PLATFORMS:{','.join(missing)}\")

for r in target:
    pub = r.get('published_at')
    act = r.get('is_active')
    if not pub or pub == '' or not act:
        print(f\"{r.get('platform')}:active={act}:published_at={pub!r}\")
" 2>/dev/null)
      py_rc=$?
      rm -f "$tmp_releases"

      # A python3 parse crash leaves result="" which would otherwise fall
      # through to the PASS branch below — treat a non-zero exit as
      # "record NOT verified", never a silent green.
      if [ "$py_rc" -ne 0 ]; then
        issues="${issues}$brand v$version: preflight parse error (python3 exit $py_rc — record NOT verified)\n"
      elif [ "$result" = "NO_RECORDS" ]; then
        # Pre-ship invocation: records don't exist yet — that's expected
        # before the release dispatches. SKIP, don't fail.
        no_records="${no_records}$brand v$version "
      elif [ -n "$result" ]; then
        issues="${issues}$brand v$version: $result\n"
      fi
    done

    if [ -n "$issues" ]; then
      record G3.records FAIL "records have published_at=null or is_active=false"
      printf '%b' "$issues" | sed 's/^/    /'
    elif [ -n "$no_records" ]; then
      # All requested versions have no record yet — running pre-ship.
      record G3.records SKIP "no records yet for ${no_records}— run again post-ship"
    else
      record G3.records PASS "all records have is_active=true + published_at non-null"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Gate 4 — Backend buildinfo embedded.go freshness.
#
# Production deploy webhook builds the backend image from the `backend/`
# context only — `.git/` is unavailable so runtime/debug.ReadBuildInfo()
# can't auto-embed VCS metadata, and the webhook also doesn't pass
# --build-arg for ldflags injection. The committed embedded.go (generated
# by backend/scripts/regenerate_buildinfo.sh) is the only source of truth
# the binary sees in production. Stale embedded.go → /version reports the
# wrong SHA → incident triage gets misled.
# -----------------------------------------------------------------------------
echo
echo "== Gate 4 — Backend buildinfo embedded.go freshness =="

embedded_file="backend/internal/buildinfo/embedded.go"
if [ ! -f "$embedded_file" ]; then
  record G4.embedded SKIP "$embedded_file not present (backend buildinfo gate skipped)"
else
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  embedded_sha="$(grep -E '^[[:space:]]*embeddedGitSHA[[:space:]]*=' "$embedded_file" | sed -E 's/.*"([^"]*)".*/\1/' | head -1)"

  if [ -z "$embedded_sha" ]; then
    record G4.embedded FAIL "could not parse embeddedGitSHA from $embedded_file"
  elif [ "$embedded_sha" = "$head_sha" ]; then
    record G4.embedded PASS "embeddedGitSHA matches HEAD ($head_sha)"
  else
    record G4.embedded FAIL "embeddedGitSHA=$embedded_sha but HEAD=$head_sha — run: bash backend/scripts/regenerate_buildinfo.sh && git add $embedded_file"
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo
echo "== Preflight summary =="
fail_count=0
warn_count=0
for r in "${RESULTS[@]}"; do
  status="${r%%|*}"
  rest="${r#*|}"
  id="${rest%%|*}"
  detail="${rest#*|}"
  printf '%-6s %-20s %s\n' "$status" "$id" "$detail"
  case "$status" in
    FAIL) fail_count=$((fail_count + 1)) ;;
    WARN) warn_count=$((warn_count + 1)) ;;
  esac
done

echo
if [ "$fail_count" -gt 0 ]; then
  printf '\033[0;31m%d gate(s) FAILED — do not tag.\033[0m\n' "$fail_count"
  exit 1
fi
if [ "$warn_count" -gt 0 ]; then
  if [ "$ALLOW_WARNINGS" = "1" ]; then
    printf '\033[0;33m%d warning(s) — accepted via --allow-warnings flag.\033[0m\n' "$warn_count"
    printf '\033[0;33mProceeding despite warnings — make sure each is reviewed.\033[0m\n'
    exit 0
  fi
  printf '\033[0;31m%d warning(s) — not safe to tag.\033[0m\n' "$warn_count"
  printf '\033[0;31mResolve the warnings, or re-run with --allow-warnings if each is explicitly acceptable.\033[0m\n'
  exit 1
fi
printf '\033[0;32mPreflight clean. Safe to tag.\033[0m\n'
exit 0
