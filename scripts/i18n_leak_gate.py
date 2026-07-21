#!/usr/bin/env python3
"""
i18n Leak Gate — CI-friendly automated content-quality enforcement.

Runs 4 checks against the repo:
  1. PARITY (hard-fail) — all 15 locales must have same key tree + placeholder
     set as en.json. Already covered by localization_key_parity_test.dart but
     re-validated here so the gate is self-contained.
  2. NEW HARDCODED (hard-fail by namespace) — user-facing widget files in
     protected namespaces (home/downloads/settings/browser/etc.) cannot
     introduce new hardcoded English/Vietnamese strings outside the
     i18n-call patterns. Allow-list documents known-legacy keepers.
  3. EN-LEAKAGE BASELINE (soft-warn at threshold) — track identical-to-en
     string count per non-en locale. If a delta vs baseline.json grows
     beyond per-namespace threshold, warn (not fail) so we don't block CI
     on legacy leakage while fixing it incrementally.
  4. PROTECTED NAMESPACES (hard-fail) — keys under `downloadOptions.*`,
     `errorFeedback.*`, `rightPanel.*`, `home.quota.*`, `subscriptions.*`,
     and a few other voice-critical namespaces must never regress to EN
     literal in any locale (assumes prior voice-rewrite work).

Exit codes:
  0 = all gates PASS
  1 = HARD-FAIL — parity, new hardcoded in protected widget, or protected
      namespace EN regression
  2 = SOFT-WARN only (legacy leakage drift), but no hard regression

Usage:
  python3 scripts/i18n_leak_gate.py [--update-baseline]
"""
import json
import re
import sys
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRANS = ROOT / 'assets' / 'translations'
BASELINE_PATH = ROOT / 'scripts' / 'i18n_leak_baseline.json'

LOCALES = ['en','vi','es','pt','ja','ar','de','fr','hi','id','ko','ru','th','tr','zh']

# Namespaces that have been voice-rewritten and must never regress to EN literal
# in any non-en locale (these were specifically translated in Path A + audit rounds).
PROTECTED_NAMESPACES = {
    'downloadOptions',
    'rightPanel',
    'errorFeedback',
    'home.quota',
    'subscriptions',
    'browser.history',
    'browser.tabsTitle',  # newTabTitle / incognitoTabTitle
    'tray',
    'formatters',
    'settingsMedia',
    'settingsNetwork',
}

# Per-namespace EN-leakage threshold (soft-warn budget).
# Format: namespace_prefix -> max allowed identical-to-en keys per non-en locale
LEAKAGE_BUDGET = {
    # Voice-rewritten namespaces — should be ~0 (protected check handles this)
    'downloadOptions.': 0,
    'rightPanel.': 0,
    'errorFeedback.': 0,
    # Top visible UI — moderate budget
    'home.': 30,
    'downloads.': 30,
    'common.': 10,
    'settings.': 80,
    # Lower visibility — wider budget while fixing incrementally
    'browser.': 50,
    'player.': 80,
    'converter.': 120,
    # Default for anything else
    '_default': 60,
}

# Acronyms / proper nouns that are LEGITIMATELY identical to en in many locales
# (e.g., platform names YouTube/TikTok, format names MP4/WebM, tech terms).
LEGITIMATE_IDENTICAL_PREFIXES = (
    'platforms.',
    'platformLogin.',
    'app.name',
    'app.title',
    'mediaInfo.',
    'settingsBinaryComponents.',
    'settingsBinaries.',
    'qualityDialog.quality',  # "Quality" short label often same
)

# Widget file patterns we treat as user-facing (vs. data/service layer)
PROTECTED_WIDGET_DIRS = [
    'lib/features/home/presentation',
    'lib/features/downloads/presentation',
    'lib/features/browser/presentation',
    'lib/features/settings/presentation',
    'lib/features/premium/presentation',
    'lib/features/player/presentation',
    'lib/features/assistant/presentation',
    'lib/features/support/presentation',
    'lib/features/youtube_search/presentation',
    'lib/features/youtube_channel/presentation',
    'lib/features/youtube_playlist/presentation',
    'lib/features/floating_capture/presentation',
    'lib/features/converter/presentation',
    'lib/core/navigation',
    'lib/core/widgets',
]

# Hardcoded user-facing pattern: Text(/tooltip:/hintText:/labelText:/message:/title:/label:/content:/subtitle:
# with quoted string starting with letter, len >= 5
HARDCODED_PATTERN = re.compile(
    r"(?:Text|tooltip|hintText|labelText|message|title|label|content|subtitle)\s*[:(]\s*"
    r"['\"]([A-Za-zÀ-ỹ][^'\"]{4,})['\"]"
)

EXCLUSIONS = [
    'AppLocalizations', 'debugPrint', 'TextStyle', 'TextEditing',
    'TextDirection', 'TextOverflow', 'TextInputType', 'TextAlign',
    'TextSpan', 'TextScaler', 'TextHeight', 'TextBaseline', 'TextField',
    'TextFormField', 'TextInputAction', 'TextCapitalization',
    'TextDecoration', 'TextTheme', 'TextSelectionHandle',
    'TooltipTriggerMode', '.tr()', "'package:", '"package:',
    'appLogger', 'google_fonts', 'hintStyle', 'fontFamily',
    "case '", "key: '", "Key('", 'theme.textTheme', 'titleSmall',
    'titleMedium', 'titleLarge', 'displaySmall', 'displayMedium',
    'displayLarge', 'labelSmall', 'labelMedium', 'labelLarge',
    'bodySmall', 'bodyMedium', 'bodyLarge', 'fromAddress',
]

# Allow-list — known-legitimate hardcoded strings (acronyms, format names,
# placeholder data, etc.) we don't want to flag. Format:
# {file_relative: {line: "string value"}}
HARDCODED_ALLOWLIST = {
    'lib/features/home/presentation/widgets/command_bar_preset_chip.dart': {
        # Format name acronyms — TERMINOLOGY canonical
        367: 'WebM', 372: 'MKV', 387: 'FLAC',
    },
    'lib/features/downloads/presentation/widgets/add_edit_sorting_rule_dialog.dart': {
        23: 'Sample Video',  # placeholder data
    },
    'lib/features/premium/presentation/screens/premium_upgrade_screen.dart': {
        # Standard email format placeholder hint
        1289: 'email@example.com', 1398: 'email@example.com',
        1434: 'email@example.com',
    },
    'lib/features/settings/presentation/widgets/settings_general_section.dart': {
        # Language dropdown items — correctly displayed in native form
        87: 'English', 88: 'Tiếng Việt', 89: 'Español', 90: 'Português',
        91: '日本語', 92: '한국어', 93: '中文', 94: 'Deutsch',
        95: 'Français', 96: 'Русский', 97: 'العربية', 98: 'हिन्दी',
        99: 'Bahasa Indonesia', 100: 'ภาษาไทย', 101: 'Türkçe',
    },
    'lib/features/youtube_search/presentation/widgets/video_detail_panel.dart': {
        # Technical metadata values that are universal acronyms
        346: 'YT-DLP',  # legacy — should migrate (see Round 7), kept for grace
    },
}


def flatten(d, prefix=''):
    """Flatten nested dict into dotted-key dict."""
    out = {}
    for k, v in d.items():
        nk = f'{prefix}.{k}' if prefix else k
        if isinstance(v, dict):
            out.update(flatten(v, nk))
        else:
            out[nk] = v
    return out


def load_locale(loc: str) -> dict:
    return flatten(json.load(open(TRANS / f'{loc}.json', encoding='utf-8')))


def is_legitimate_identical(key: str) -> bool:
    for prefix in LEGITIMATE_IDENTICAL_PREFIXES:
        if key.startswith(prefix):
            return True
    return False


def get_leakage_budget(key: str) -> int:
    """Return per-namespace EN-leakage budget for a given key."""
    for prefix, budget in LEAKAGE_BUDGET.items():
        if prefix == '_default':
            continue
        if key.startswith(prefix):
            return budget
    return LEAKAGE_BUDGET['_default']


# ── Gate 1: Parity ──────────────────────────────────────────────────────
def gate_parity(en_keys):
    failures = []
    placeholder_re = re.compile(r'\{[A-Za-z0-9_]+\}')
    en_flat = load_locale('en')
    for loc in LOCALES[1:]:
        cur = load_locale(loc)
        missing = en_keys - set(cur.keys())
        extras = set(cur.keys()) - en_keys
        if missing:
            failures.append(f"PARITY [{loc}] missing {len(missing)} keys (sample: {sorted(missing)[:3]})")
        if extras:
            failures.append(f"PARITY [{loc}] extra {len(extras)} keys not in en (sample: {sorted(extras)[:3]})")
        # Placeholder check
        for k in en_keys & set(cur.keys()):
            en_phs = set(placeholder_re.findall(str(en_flat.get(k, ''))))
            cur_phs = set(placeholder_re.findall(str(cur.get(k, ''))))
            if en_phs != cur_phs:
                failures.append(f"PARITY [{loc}] placeholder mismatch at '{k}': en={en_phs} != {loc}={cur_phs}")
    return failures


# ── Gate 2: New hardcoded in protected widget files ─────────────────────
def is_skipped(line: str) -> bool:
    s = line.strip()
    if s.startswith('//') or s.startswith('*') or s.startswith('///'):
        return True
    for excl in EXCLUSIONS:
        if excl in line:
            return True
    return False


# Vietnamese-specific character class: catches all VN diacritics + đĐ.
# Used by gate_vietnamese_hardcoded to flag any Vietnamese literal anywhere
# under lib/ (regardless of widget vs data layer) — the existing
# HARDCODED_PATTERN only fires inside specific field assignments
# (`Text(`, `tooltip:`, `title:`, etc.), so literals like
# `name: 'Tự động'` or `description: 'Bấm vào ảnh để xem'` slipped through
# until a tester catch in 2026-05-21.
VIETNAMESE_CHAR_CLASS = (
    r'ăâêôơưđĐ'
    r'áàảãạằẳẵặấầẩẫậ'
    r'éèẻẽẹếềểễệ'
    r'íìỉĩị'
    r'óòỏõọốồổỗộớờởỡợ'
    r'úùủũụứừửữự'
    r'ýỳỷỹỵ'
    r'ÁÀẢÃẠẰẲẴẶẤẦẨẪẬ'
    r'ÉÈẺẼẸẾỀỂỄỆ'
    r'ÍÌỈĨỊ'
    r'ÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢ'
    r'ÚÙỦŨỤỨỪỬỮỰ'
    r'ÝỲỶỸỴ'
)
VIETNAMESE_LITERAL_RE = re.compile(
    r"['\"]([^'\"\\n]*[" + VIETNAMESE_CHAR_CLASS + r"][^'\"\\n]*)['\"]"
)
VIETNAMESE_SCAN_EXCLUDE = (
    '.g.dart', '.freezed.dart', '/test/', '/build/', '/.dart_tool/',
)


def gate_vietnamese_hardcoded(baseline_vn):
    """Scan all `lib/**/*.dart` for Vietnamese-diacritic string literals.
    Catches the bug class that HARDCODED_PATTERN misses: hardcoded VI
    inside `name:`, `body:`, enum returns, notification payloads, etc.

    Same baseline semantics as `gate_hardcoded`: items already in
    `baseline_vn` → soft warn (legacy); new items → hard fail.
    """
    hard_fails = []
    soft_warns = []
    current_set = set()
    lib_dir = ROOT / 'lib'
    for dart_file in lib_dir.rglob('*.dart'):
        rel = str(dart_file.relative_to(ROOT))
        if any(x in rel for x in VIETNAMESE_SCAN_EXCLUDE):
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        for i, line in enumerate(content.split('\n'), 1):
            if is_skipped(line):
                continue
            # Skip strings inside translation JSON keys (e.g. `'home.x'.tr()`)
            # Treat appLogger/Sentry/throw context as skipped via EXCLUSIONS
            for m in VIETNAMESE_LITERAL_RE.finditer(line):
                txt = m.group(1).strip()
                if len(txt) < 2:
                    continue
                sig = f"{rel}::{txt}"
                current_set.add(sig)
                if sig in baseline_vn:
                    soft_warns.append(f"VN-HARDCODED-LEGACY {rel}:{i} '{txt[:50]}'")
                else:
                    hard_fails.append(f"VN-HARDCODED-NEW {rel}:{i} '{txt[:60]}'")
    return hard_fails, soft_warns, current_set


# ── Gate 6: dispatch-getter resolution (Tier 7, added 2026-05-21) ──────
#
# `AppLocalizations` exposes dispatch getters that resolve i18n keys at
# call time from a runtime ID, e.g. `builtinPresetName(presetId)` →
# `'builtinPreset.$presetId'.tr()`. The other 5 gates can ONLY detect
# missing-key parity OR static hardcoded literals — they miss the bug
# class where the Dart side passes IDs that have no matching en.json key.
#
# Real bug shipped 2026-05-21: em added `builtinPreset.mp4_1080p` (Dart
# constant identifier name) but `BuiltinPresetIds.mp4_1080p` has the
# STRING VALUE `'1080p_mp4'`. Runtime warning:
#   [Easy Localization] Localization key [builtinPreset.1080p_mp4] not found
# Gate ✅ green because key tree was internally consistent — only a
# *runtime resolution* check catches Dart-identifier-vs-string-value drift.
#
# Registry maps each dispatch getter to (key prefix, expected ID source).
# ID source is either:
#   - a tuple of literal IDs (when the set is small + stable), or
#   - a `(file, anchor_regex, extractor_regex)` triplet that scans the
#     code itself so the registry doesn't drift away from the enum/class
#     it shadows.
DISPATCH_RESOLUTIONS = {
    'builtinPresetName': {
        'key_template': 'builtinPreset.{}',
        'ids_static': (
            'auto', '1080p_mp4', '720p_compact',
            'audio_mp3_320', '4k_max', 'archive',
        ),
    },
    'diagnosticsExplanation': {
        'key_template': 'diagnostics.explanation.{}',
        # Mirrors DownloadErrorCode enum values (22 cases).
        'ids_static': (
            'networkOffline', 'networkTimeout', 'serverError',
            'connectionRefused', 'sslError', 'videoNotFound',
            'geoRestricted', 'loginRequired', 'ageRestricted',
            'formatUnavailable', 'rateLimited', 'accessDenied',
            'contentUnavailable', 'ytdlpBinaryMissing',
            'binaryNotAvailable', 'jsRuntimeUnavailable',
            'cookieDbLocked', 'ffmpegError', 'diskFull',
            'permissionDenied', 'pathNotFound', 'unknown',
        ),
    },
    'errorFeedbackHint': {
        'key_template': 'errorFeedback.hint.{}',
        'ids_static': (
            'networkOffline', 'networkTimeout', 'serverError',
            'connectionRefused', 'sslError', 'videoNotFound',
            'geoRestricted', 'loginRequired', 'ageRestricted',
            'formatUnavailable', 'rateLimited', 'accessDenied',
            'contentUnavailable', 'ytdlpBinaryMissing',
            'binaryNotAvailable', 'jsRuntimeUnavailable',
            'cookieDbLocked', 'ffmpegError', 'diskFull',
            'permissionDenied', 'pathNotFound', 'unknown',
        ),
    },
    'errorFeedbackTitle': {
        'key_template': 'errorFeedback.title.{}',
        'ids_static': (
            'networkOffline', 'networkTimeout', 'serverError',
            'connectionRefused', 'sslError', 'videoNotFound',
            'geoRestricted', 'loginRequired', 'ageRestricted',
            'formatUnavailable', 'rateLimited', 'accessDenied',
            'contentUnavailable', 'ytdlpBinaryMissing',
            'binaryNotAvailable', 'jsRuntimeUnavailable',
            'cookieDbLocked', 'ffmpegError', 'diskFull',
            'permissionDenied', 'pathNotFound', 'unknown',
        ),
    },
    'conversionStatusLabel': {
        'key_template': 'conversionStatus.{}',
        'ids_static': (
            'queued', 'probing', 'converting', 'paused',
            'completed', 'failed', 'cancelled',
        ),
    },
    'outputFormatCategoryLabel': {
        'key_template': 'outputFormatCategory.{}',
        'ids_static': ('video', 'audio', 'animatedImage'),
    },
    'watermarkPositionLabel': {
        'key_template': 'watermarkPosition.{}',
        'ids_static': (
            'topLeft', 'topRight', 'bottomLeft', 'bottomRight', 'center',
        ),
    },
    'mediaTypeLabel': {
        'key_template': 'mediaType.{}',
        'ids_static': ('video', 'audio', 'image', 'subtitle'),
    },
    'keyboardShortcutsSection': {
        'key_template': 'keyboardShortcuts.section.{}',
        # Extract from call sites — the dialog enumerates them inline.
        'ids_dynamic': (
            'lib/features/player/presentation/widgets/keyboard_shortcuts_dialog.dart',
            r"keyboardShortcutsSection\('([a-zA-Z]+)'\)",
        ),
    },
    'keyboardShortcutsItem': {
        'key_template': 'keyboardShortcuts.item.{}',
        'ids_dynamic': (
            'lib/features/player/presentation/widgets/keyboard_shortcuts_dialog.dart',
            r"keyboardShortcutsItem\('([a-zA-Z]+)'\)",
        ),
    },
}


def gate_dispatch_resolution(en_keys: set) -> 'tuple[list[str], list[str]]':
    """For every dispatch getter in DISPATCH_RESOLUTIONS, verify every
    runtime ID it can receive resolves to a real en.json key.

    Catches the 2026-05-21 bug class where the Dart identifier name and
    the underlying string value disagree, so the static i18n key is
    spelled wrong (e.g. `builtinPreset.mp4_1080p` instead of
    `builtinPreset.1080p_mp4`).
    """
    hard_fails: list[str] = []
    soft_warns: list[str] = []
    for getter, spec in DISPATCH_RESOLUTIONS.items():
        ids: list[str] = []
        if 'ids_static' in spec:
            ids.extend(spec['ids_static'])
        if 'ids_dynamic' in spec:
            rel, pattern = spec['ids_dynamic']
            src_path = ROOT / rel
            if not src_path.exists():
                soft_warns.append(
                    f"DISPATCH-SOURCE-MISSING {getter}: source file gone — {rel}"
                )
                continue
            try:
                src = src_path.read_text(encoding='utf-8')
            except Exception:
                continue
            ids.extend(sorted(set(re.findall(pattern, src))))
        seen = set()
        for vid in ids:
            if vid in seen:
                continue
            seen.add(vid)
            resolved = spec['key_template'].format(vid)
            if resolved not in en_keys:
                hard_fails.append(
                    f"DISPATCH-UNRESOLVED {getter}('{vid}') → '{resolved}' "
                    f"missing in en.json"
                )
    return hard_fails, soft_warns


# ── Gate 7: cross-brand identity leak in i18n strings ──────────────────
#
# Catches strings inside assets/translations/*.json that embed an identifier
# belonging to ONE brand but get rendered for ALL brands (or the wrong
# brand). The 2026-05-27 regression: `premium.invalidKeyFormat` hardcoded
# "Expected: SVID-XXXX-..." in every locale, so VidCombo users saw the
# Svid brand in their license-activation error dialog.
#
# Detection rule: any locale string value containing a brand identity token
# (SVID-, VIDCOMBO-, brand display name, brand URL, brand bundle id).
# Fix pattern: replace with `{placeholder}` and inject via
# `BrandConfig.current.<brand-aware getter>` at call site.
BRAND_LEAK_PATTERNS = [
    # License key prefixes (canonical Go format identifiers).
    re.compile(r'SVID-[A-Z0-9X]'),
    re.compile(r'VIDCOMBO-[A-Z0-9X]'),
    # Brand display names (case-sensitive — avoids "svid" substring in URLs).
    re.compile(r'\bSvid\b'),
    re.compile(r'\bVidCombo\b'),
    # Brand URLs / bundle ids.
    re.compile(r'svid\.app'),
    re.compile(r'svid\.net'),
    re.compile(r'vidcombo\.com'),
    re.compile(r'vidcombo\.net'),
    re.compile(r'com\.svid\.'),
    re.compile(r'com\.tinasoft\.vidcombo'),
]


def gate_brand_leak(baseline_brand_leak):
    """Return (hard_fails, soft_warns). Same baseline semantics as the
    hardcoded gate: items present in baseline = soft warn; new items = fail.

    Walks every locale JSON, recursively collects string values, matches
    against BRAND_LEAK_PATTERNS. Findings surface as
    `{locale}/{dotted.key}: {matched-token} :: {string-preview}`.
    """
    hard_fails: list[str] = []
    soft_warns: list[str] = []
    current_set: set[str] = set()

    def walk(d, path=''):
        out = []
        if isinstance(d, dict):
            for k, v in d.items():
                out.extend(walk(v, f'{path}.{k}' if path else k))
        elif isinstance(d, str):
            out.append((path, d))
        return out

    for jf in sorted((ROOT / 'assets' / 'translations').glob('*.json')):
        loc = jf.stem
        with jf.open(encoding='utf-8') as f:
            d = json.load(f)
        for keypath, s in walk(d):
            for pat in BRAND_LEAK_PATTERNS:
                m = pat.search(s)
                if m:
                    sig = f"{loc}/{keypath}::{pat.pattern}"
                    current_set.add(sig)
                    msg = (
                        f"BRAND-LEAK [{loc}] {keypath}: "
                        f"'{m.group(0)}' in {repr(s)[:80]}"
                    )
                    if sig in baseline_brand_leak:
                        soft_warns.append(msg)
                    else:
                        hard_fails.append(msg)
                    break  # one match per key is enough
    return hard_fails, soft_warns, current_set


def gate_hardcoded(baseline_hardcoded):
    """Return (hard_fails, soft_warns). Baseline mode: items present in
    baseline_hardcoded set are recorded as known-state (soft warn);
    new items not in baseline = hard fail."""
    hard_fails = []
    soft_warns = []
    new_hardcoded_set = set()
    for scope in PROTECTED_WIDGET_DIRS:
        p = ROOT / scope
        if not p.exists():
            continue
        for dart_file in p.rglob('*.dart'):
            rel = str(dart_file.relative_to(ROOT))
            try:
                content = dart_file.read_text(encoding='utf-8')
            except Exception:
                continue
            allowed = HARDCODED_ALLOWLIST.get(rel, {})
            for i, line in enumerate(content.split('\n'), 1):
                if is_skipped(line):
                    continue
                m = HARDCODED_PATTERN.search(line)
                if not m:
                    continue
                txt = m.group(1).strip()
                if len(txt) < 5:
                    continue
                if re.match(r'^[a-z_]+$', txt) or re.match(r'^[a-z_]+\.[a-z_]+', txt):
                    continue
                if allowed.get(i) == txt:
                    continue
                # Stable signature: file + content (line numbers shift on edits)
                sig = f"{rel}::{txt}"
                new_hardcoded_set.add(sig)
                if re.match(r'^[A-Z][A-Z0-9 \-]*$', txt) and len(txt) <= 12:
                    soft_warns.append(f"HARDCODED-ACRONYM {rel}:{i} '{txt}'")
                    continue
                if sig in baseline_hardcoded:
                    # Known backlog — soft warn
                    soft_warns.append(f"HARDCODED-LEGACY {rel}:{i} '{txt[:50]}'")
                else:
                    hard_fails.append(f"HARDCODED-NEW {rel}:{i} '{txt[:60]}'")
    return hard_fails, soft_warns, new_hardcoded_set


# ── Gate 3: EN-leakage drift vs baseline ────────────────────────────────
def measure_leakage() -> 'dict[str, dict[str, int]]':
    """Returns {locale: {namespace_prefix: identical_count}}."""
    en_flat = load_locale('en')
    result = {}
    for loc in LOCALES[1:]:
        cur = load_locale(loc)
        counts = {}
        for k in en_flat:
            if is_legitimate_identical(k):
                continue
            if not isinstance(en_flat[k], str) or len(en_flat[k]) < 3:
                continue
            if k in cur and cur[k] == en_flat[k]:
                # Bucket by top-level namespace
                ns = k.split('.', 1)[0]
                counts[ns] = counts.get(ns, 0) + 1
        result[loc] = counts
    return result


def gate_leakage_drift(current, baseline):
    """Compare current leakage to baseline. Warns if grew."""
    hard_fails = []
    soft_warns = []
    if baseline is None:
        soft_warns.append("LEAKAGE: no baseline.json found — first run, recording baseline")
        return hard_fails, soft_warns
    for loc, ns_counts in current.items():
        base_counts = baseline.get(loc, {})
        for ns, count in ns_counts.items():
            base = base_counts.get(ns, 0)
            if count > base:
                delta = count - base
                soft_warns.append(
                    f"LEAKAGE-DRIFT [{loc}] {ns}.* grew +{delta} (was {base}, now {count})"
                )
    return hard_fails, soft_warns


# ── Gate 4: Protected namespaces no EN regression ───────────────────────
def gate_protected_namespaces(baseline):
    """Baseline mode: only hard-fail if a key that was previously
    properly translated regresses back to EN literal. Legacy EN leakage
    (key always was EN in baseline) is recorded as known-state, not failed.

    Baseline format includes per-key state, so we know which keys were
    translated vs EN-fallback at baseline capture time."""
    failures = []
    if baseline is None:
        # First run: no baseline yet, can't detect regression
        return failures
    en_flat = load_locale('en')
    baseline_keys = baseline.get('_protected_translated_keys', {})
    for loc in LOCALES[1:]:
        cur = load_locale(loc)
        known_translated = set(baseline_keys.get(loc, []))
        for k in known_translated:
            if k not in cur:
                continue
            if not isinstance(en_flat.get(k), str):
                continue
            # Was translated at baseline (loc value != en value at that time).
            # Now check if regressed to == en literal.
            if cur[k] == en_flat[k] and len(en_flat[k]) > 4:
                failures.append(
                    f"PROTECTED-NS-REGRESSION [{loc}] '{k}' regressed to en literal '{en_flat[k][:50]}'"
                )
    return failures


def measure_translated_keys_in_protected_ns():
    """For baseline: snapshot which keys in protected namespaces are
    currently properly translated (loc value != en value). Stored so
    future runs can detect regressions."""
    en_flat = load_locale('en')
    result = {}
    for loc in LOCALES[1:]:
        cur = load_locale(loc)
        translated = []
        for k in en_flat:
            ns = k.split('.', 1)[0]
            in_protected = ns in PROTECTED_NAMESPACES or any(
                k.startswith(p + '.') for p in PROTECTED_NAMESPACES
            )
            if not in_protected:
                continue
            if not isinstance(en_flat[k], str) or len(en_flat[k]) < 5:
                continue
            if is_legitimate_identical(k):
                continue
            if k in cur and cur[k] != en_flat[k]:
                translated.append(k)
        result[loc] = sorted(translated)
    return result


# ── Main ────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--update-baseline', action='store_true',
                        help='Update baseline.json with current leakage measurements')
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    print("=" * 70)
    print("i18n LEAK GATE")
    print("=" * 70)

    # Gate 1: parity
    en_flat = load_locale('en')
    en_keys = set(en_flat.keys())
    print(f"\nen.json: {len(en_keys)} keys")
    parity_fails = gate_parity(en_keys)
    if parity_fails:
        print(f"❌ PARITY ({len(parity_fails)} failures)")
        for f in parity_fails[:10]:
            print(f"  {f}")
        if len(parity_fails) > 10:
            print(f"  ... and {len(parity_fails)-10} more")
    else:
        print("✅ PARITY: 15 locales, identical key tree + placeholder set")

    # Load baseline once
    baseline = None
    if BASELINE_PATH.exists():
        baseline = json.load(open(BASELINE_PATH))

    # Gate 2: hardcoded (baseline-aware)
    baseline_hardcoded = set(baseline.get('_hardcoded_baseline', [])) if baseline else set()
    hardcoded_fails, hardcoded_warns, current_hardcoded_set = gate_hardcoded(baseline_hardcoded)
    if hardcoded_fails:
        print(f"\n❌ HARDCODED ({len(hardcoded_fails)} hard fails)")
        for f in hardcoded_fails[:15]:
            print(f"  {f}")
        if len(hardcoded_fails) > 15:
            print(f"  ... and {len(hardcoded_fails)-15} more")
    else:
        print("\n✅ HARDCODED: no new hardcoded strings in protected widget dirs")
    if hardcoded_warns and args.verbose:
        print(f"  ⚠ {len(hardcoded_warns)} acronym soft-warns (review case-by-case)")

    # Gate 3: leakage drift
    current_leakage = measure_leakage()
    leakage_fails, leakage_warns = gate_leakage_drift(current_leakage, baseline)
    if leakage_fails:
        print(f"\n❌ LEAKAGE ({len(leakage_fails)})")
        for f in leakage_fails:
            print(f"  {f}")
    elif leakage_warns:
        print(f"\n⚠ LEAKAGE-DRIFT ({len(leakage_warns)} warns)")
        for w in leakage_warns[:10]:
            print(f"  {w}")
        if len(leakage_warns) > 10:
            print(f"  ... and {len(leakage_warns)-10} more")
    else:
        print("\n✅ LEAKAGE: no drift from baseline")

    # Gate 4: protected namespaces (baseline-aware)
    protected_fails = gate_protected_namespaces(baseline)
    if protected_fails:
        print(f"\n❌ PROTECTED-NS-REGRESSION ({len(protected_fails)})")
        for f in protected_fails[:15]:
            print(f"  {f}")
        if len(protected_fails) > 15:
            print(f"  ... and {len(protected_fails)-15} more")
    else:
        print("\n✅ PROTECTED NAMESPACES: no voice-rewrite regression")

    # Gate 5: Vietnamese-hardcoded sweep (whole-lib scan). Added 2026-05-21
    # after tester found VI literals leaking through HARDCODED_PATTERN
    # (field names like `name:`, `body:`, enum returns).
    baseline_vn = set(baseline.get('_vietnamese_baseline', [])) if baseline else set()
    vn_fails, vn_warns, current_vn_set = gate_vietnamese_hardcoded(baseline_vn)
    if vn_fails:
        print(f"\n❌ VN-HARDCODED ({len(vn_fails)} hard fails)")
        for f in vn_fails[:15]:
            print(f"  {f}")
        if len(vn_fails) > 15:
            print(f"  ... and {len(vn_fails)-15} more")
    else:
        print("\n✅ VN-HARDCODED: no new Vietnamese string literals in lib/")

    # Gate 6: dispatch-getter resolution. Added 2026-05-21 after a runtime
    # warning surfaced wrong key paths (`builtinPreset.mp4_1080p` instead
    # of `builtinPreset.1080p_mp4`) that all 5 prior gates considered
    # internally consistent.
    dispatch_fails, dispatch_warns = gate_dispatch_resolution(en_keys)
    if dispatch_fails:
        print(f"\n❌ DISPATCH-UNRESOLVED ({len(dispatch_fails)} hard fails)")
        for f in dispatch_fails[:15]:
            print(f"  {f}")
        if len(dispatch_fails) > 15:
            print(f"  ... and {len(dispatch_fails)-15} more")
    else:
        print("\n✅ DISPATCH-RESOLUTION: every dispatch-getter runtime ID resolves to a real en.json key")

    # Gate 7: cross-brand identity leak in i18n strings. Added 2026-05-27
    # after tester screenshot showed VidCombo app rendering "SVID-XXXX-..."
    # in license activation error — `premium.invalidKeyFormat` hardcoded
    # the Svid brand prefix in every locale.
    baseline_brand_leak = set(baseline.get('_brand_leak_baseline', []) or []) if baseline else set()
    brand_fails, brand_warns, current_brand_leak_set = gate_brand_leak(baseline_brand_leak)
    if brand_fails:
        print(f"\n❌ BRAND-LEAK ({len(brand_fails)} hard fails)")
        for f in brand_fails[:15]:
            print(f"  {f}")
        if len(brand_fails) > 15:
            print(f"  ... and {len(brand_fails)-15} more")
    else:
        print("\n✅ BRAND-LEAK: no cross-brand identity tokens in i18n strings")

    # Update baseline if requested (includes protected-key snapshot)
    if args.update_baseline:
        full_baseline = {
            **current_leakage,
            '_protected_translated_keys': measure_translated_keys_in_protected_ns(),
            '_hardcoded_baseline': sorted(current_hardcoded_set),
            '_vietnamese_baseline': sorted(current_vn_set),
            '_brand_leak_baseline': sorted(current_brand_leak_set),
        }
        json.dump(full_baseline, open(BASELINE_PATH, 'w', encoding='utf-8'),
                  indent=2, ensure_ascii=False, sort_keys=True)
        print(f"\n📝 Baseline updated: {BASELINE_PATH}")

    # Verdict
    total_hard = (
        len(parity_fails) + len(hardcoded_fails) + len(protected_fails)
        + len(leakage_fails) + len(vn_fails) + len(dispatch_fails)
        + len(brand_fails)
    )
    total_warns = (
        len(hardcoded_warns) + len(leakage_warns) + len(vn_warns)
        + len(dispatch_warns) + len(brand_warns)
    )
    print("\n" + "=" * 70)
    if total_hard > 0:
        print(f"❌ GATE FAIL: {total_hard} hard issue(s)")
        sys.exit(1)
    elif total_warns:
        print(f"⚠ GATE PASS-WITH-WARNINGS: {total_warns} soft warns")
        sys.exit(0)
    else:
        print("✅ GATE PASS: clean")
        sys.exit(0)


if __name__ == '__main__':
    main()
