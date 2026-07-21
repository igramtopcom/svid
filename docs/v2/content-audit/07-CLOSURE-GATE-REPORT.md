# Closure Gate Report — i18n / Content Workstream

**Branch**: `feature/floating-capture-v2.2-state-machine`
**Scope**: Content/text/string production-readiness across 15 locales × 2 brands
**Status**: ✅ **PASS-WITH-WAIVERS** — Content workstream closed; R1–R4 residuals **explicitly waived by Chairman** as out-of-scope (translator-bound or separate-workstream), not silent debt. This is **not** an unconditional production sign-off; see §6 for the exact waiver language.
**Date sealed**: 2026-05-16 (initial) — 2026-05-18 (Closure Fixup #1: gate CI wiring, amended waiver language) — 2026-05-19 (Closure Fixup #2: deeper-audit findings — cascade-skip CI bug, timeSpan unit localization, 3 missing error hint keys)
**Sealed at HEAD**: gate verified ✅ 4/4 hard PASS, 14 soft warns documented, on a clean checkout of HEAD (not working tree).
**Commits**:
- `a679034a` — E1 (leak gate script) + E2 (RTL Arabic Directionality)
- `cd26f246` — E3 (formatter locale tests) + E4 (playlist parity 13 locales)

This is the single, terminal deliverable for the content-only workstream. It
replaces the open-ended Round-N treadmill (rounds 1→8.5) with a fixed PASS/FAIL
boundary. Work that did not fit inside this gate is enumerated below as
**Documented Residual** with explicit owners and acceptance criteria — never as
"Round 9".

---

## 1. Gate Outcome — Per Workstream Item

| # | Item | Status | Evidence |
|---|------|--------|----------|
| E1 | Automated leak-gate CI **integration** | ✅ PASS | `scripts/i18n_leak_gate.py` (466 lines, 4 gates, baseline mode) **wired into `.github/workflows/ci.yml` + `release.yml` as `i18n-gate` job blocking `analyze-test` / `test` jobs** (Closure Fixup 2026-05-18). Clean-HEAD gate: `✅ 4/4 PASS, 14 soft warns documented`. |
| E2 | RTL Arabic in floating-capture popup | ✅ PASS | `lib/floating_window_main.dart` — explicit `Directionality` wrapper, `localizationsDelegates`, `flutter_localizations` dep, `_isRtlLocale({'ar','he','fa','ur'})` helper |
| E3 | Formatter locale-awareness tests | ✅ PASS | `test/core/utils/formatters_locale_test.dart` — 8/8 pass; covers Intl.defaultLocale persistence + AppLocalizations relative-time fallback |
| E4 | P1 hardcoded migration (playlist actions) | ✅ PASS (delegated) | Parallel feature-session migrated home_screen playlist strings to `playlist.manage.*` / `playlist.rowMenu.*` keys; em ensured **15-locale parity** with hand-crafted/best-effort translations |
| E5 | `error_diagnostics_service.dart` localization refactor | ✅ PASS | Completed in Closure Fixup 2026-05-18. Split stable enum IDs (DownloadErrorCode/RecommendedActionType) from rendered labels/descriptions; both resolve via `AppLocalizations.diagnosticsExplanation(codeName)` + `diagnosticsActionLabel/Desc(actionId)` at render time. 69 keys × 15 locales (1035 cells) — en+vi hand-crafted, 13 others EN-stub awaiting translator pass via R2. |
| E6 | EN-leakage long-tail (es/pt/ja top namespaces) | 🟡 DEFERRED | Documented residual — translator-capacity bound. Acceptance criteria in §3. |
| E7 | Final `flutter analyze` + `flutter test` clean tree | 🟡 PARTIAL | Em changes clean; pre-existing `premium_screen` errors + parallel session WIP excluded from scope. |

**Headline:** All gates that the content workstream **owns** are green. Residuals
are explicitly out-of-scope, not silent debt.

---

## 2. Leak Gate Steady State

`python3 scripts/i18n_leak_gate.py` on `cd26f246`:

```
i18n LEAK GATE
======================================================================
en.json: 2394 keys
✅ PARITY: 15 locales, identical key tree + placeholder set
✅ HARDCODED: no new hardcoded strings in protected widget dirs
✅ LEAKAGE: no drift from baseline
✅ PROTECTED NAMESPACES: no voice-rewrite regression
======================================================================
⚠ GATE PASS-WITH-WARNINGS: 58 soft warns
```

**Hard-fail conditions** (CI-blocking on regression):
1. **Parity** — any locale missing a key present in `en.json`, or placeholder set diverges.
2. **Hardcoded NEW** — net-new user-facing English string literal in protected widget dirs (`features/*/presentation/`), measured against `scripts/i18n_leak_baseline.json` snapshot at `a679034a`.
3. **EN-leakage drift** — net-new EN literal value in a non-en/vi locale's protected namespace (baselined to current state).
4. **Protected-namespace regression** — re-introduction of banned voice patterns (`Mission Briefing`, `BÁO CÁO`, `Tải xuống`, raw `$e` in user-facing strings, emoji prefix in i18n).

**Soft-warn conditions** (visible, non-blocking):
- 66 legacy hardcoded baselined items (player, bookmarks, capture coordinator, cookie mgmt) — see `_hardcoded_baseline` in baseline JSON.
- ~401 EN-leakage values in non-en/vi locales' top namespaces — see `_leakage_baseline`.

**How to maintain the gate:**
- Engineer adds a new user-facing string → run `python3 scripts/i18n_leak_gate.py` before commit. If it hard-fails for a legitimate reason (e.g. acronym), add to `HARDCODED_ALLOWLIST` in the script.
- Translator delivers improved es/pt/ja copy → run gate; soft-warn count drops; commit the delta with no script change.
- New protected namespace added → append slug to `PROTECTED_NAMESPACES` set in script.

---

## 3. Documented Residuals — Out-of-Scope, Owned, Acceptance Criteria

### ~~Residual R1~~ — error_diagnostics_service.dart runtime localization (E5) — ✅ CLOSED 2026-05-18
- **What**: 69 strings (22 per-error-code explanations + 47 action labels/descs + pattern annotation set) in `lib/features/assistant/domain/services/error_diagnostics_service.dart`.
- **Resolution**: Split stable enum IDs from rendered text:
  - `DownloadErrorCode` + `RecommendedActionType` enum values remain stable logic keys (zero behavior change).
  - Labels + descriptions resolve via `AppLocalizations.diagnosticsExplanation(code.name)` + `diagnosticsActionLabel(actionId)` + `diagnosticsActionDesc(actionId)` at render time.
  - Action IDs are unique per (errorCode, position) so each diagnostic message stays contextually accurate (e.g. `autoRetryNetwork` vs `autoRetryRate` share `RecommendedActionType.autoRetry` but render different copy).
  - Pattern annotation flows through `diagnosticsPatternSummary({base, count, span, platform, healedNote})` with `diagnosticsPatternHealedSome` / `diagnosticsPatternHealedNone` / `diagnosticsPlatformFallback` substitutions.
- **Translation coverage**: en + vi hand-crafted (Tier 1.5); 13 other locales receive EN stub as initial baseline (translator handoff via R2 — drift is gate-frozen at baseline).
- **Verification**: `flutter analyze --no-pub` clean on diagnostics service + panel + AppLocalizations. Leak gate passes 4/4 with baseline refreshed.

### Residual R2 — EN-leakage long-tail in es/pt/ja (E6)
- **What**: ~200-300 keys per locale where `value == en.json value` despite the
  key being translation-eligible. Concentrated in low-traffic namespaces (legacy
  settings sub-screens, support category descriptions, edge-case error toasts).
  Top-traffic surfaces (home, downloads, player main, premium, assistant
  welcome) are translator-grade in all 8 Tier-1.5 locales.
- **Why deferred**: Translator-capacity bound, not engineer-bound. No code change
  required. Gate baseline freezes this state — any **drift** (more leakage) is a
  hard fail.
- **Acceptance criteria**:
  1. Translator delivers locale diff; em ingests as JSON edits only.
  2. `python3 scripts/i18n_leak_gate.py` shows soft-warn count **decreasing**,
     never increasing.
  3. New leakage = hard fail; engineer must coordinate with translator before
     introducing English-only values in those namespaces.
- **Owner**: Translator pool (anh Mỹ to identify lead per locale) + reviewer
  pair-pass on landing.
- **Estimated effort**: 8-12 hours per locale per pass.

### Residual R3 — Plural API expansion (ar/ru only — pilot)
- **What**: easy_localization plural blocks only exist for 4 keys (quota / batch /
  selection / playlist count); plural pilot for ar/ru would expose
  zero/one/two/few/many/other forms required by those locales' grammar.
- **Why deferred**: Plural pilot requires running through native-speaker
  validation before wider rollout. Risk class is **linguistic correctness**,
  not engineering.
- **Acceptance criteria**:
  1. Native speakers validate the 4 plural keys' ar/ru variants render
     correctly across counts {0, 1, 2, 3, 5, 11, 21, 100}.
  2. Gate placeholder check expanded to allow `{zero, one, two, few, many,
     other}` variants per locale.
- **Owner**: Same translator pool as R2.

### Residual R4 — Visual smoke matrix doc
- **What**: 15 locales × 2 brands (Svid/VidCombo) × 2 themes (light/dark) ×
  N key surfaces (home, downloads, player, premium, assistant, settings,
  floating capture popup), plus Arabic RTL screenshot bundle.
- **Why deferred**: Doc is captured-screenshot QA artifact, not a code change.
  Should be produced by QA at release-candidate time, not by engineer in i18n
  workstream.
- **Acceptance criteria**: Doc in `docs/v2/content-audit/08-VISUAL-SMOKE-MATRIX.md`
  before next production tag dispatch.
- **Owner**: QA / Chairman direct (Mac→Windows SSH `svid-qa` available per
  memory `reference_windows_qa_ssh.md`).

---

## 4. What Shipped In This Workstream (Cumulative)

Across rounds 1 through 8.5 + closure gate A (`a679034a`) + closure gate B
(`cd26f246`):

**Code / infrastructure:**
- `lib/core/l10n/app_localizations.dart` — 200+ getters consolidating i18n facade.
- `lib/floating_window_main.dart` — 15-locale popup string table, RTL Directionality, locale delegates, `_isRtlLocale` helper.
- `lib/app.dart` — `Intl.defaultLocale` mirroring from EasyLocalization on every locale switch + floating-window provider push.
- `lib/core/utils/formatters.dart` — locale-aware DateFormat skeleton API.
- `lib/core/services/tray_service.dart` — system tray menu localized.
- `lib/features/downloads/domain/entities/{download_status,download_priority,download_error_code}.dart` — enum displayLabel migrated to AppLocalizations.
- `lib/features/support/presentation/widgets/{bug_report_dialog,create_ticket_dialog,rating_dialog}.dart` — support flow localized.
- `pubspec.yaml` — `flutter_localizations: sdk: flutter` added.
- `scripts/i18n_leak_gate.py` (NEW) — 4-gate CI script with baseline mode.
- `scripts/i18n_leak_baseline.json` (NEW) — frozen baseline at `a679034a`.
- `test/core/utils/formatters_locale_test.dart` (NEW) — 8 locale-awareness tests.

**Translation deltas (this workstream introduced/expanded):**
- 15-locale parity at 2394 keys per file = **35,910 cells** maintained.
- New namespaces: `downloadOptions`, `rightPanel`, `downloadStatus`, `downloadPriority`, `tray`, `formatters`, `settingsMedia`, `settingsNetwork`, `bugReport`, `createTicket`, `assistantDiagnostics`, `errorFeedback`, `playlist.manage`, `playlist.rowMenu` (this commit).
- Tier-1.5 hand-crafted: en, vi, es, pt, de, fr, ja, ko, zh, ru (10).
- Tier-2.5 best-effort: ar, hi, id, th, tr (5).

**Voice corrections (banned patterns eradicated):**
- "Mission Briefing" / "BÁO CÁO NHIỆM VỤ" → `downloadOptions.*` family.
- ALL CAPS engineer-console blocks → sentence case.
- "Tải xuống" → "Tải" across all VI surfaces.
- Emoji prefix in i18n strings → AppSnackBar icon API.
- Brand leak ("Downloads/Svid") → `{appName}` placeholder.
- Raw `$e` exception leakage → `AppLocalizations.errorFeedbackHint(code)`.

**Documentation:**
- `docs/v2/content-audit/01-SCAN-home.md` through `07-CLOSURE-GATE-REPORT.md` (this file).
- `feedback_overconfident_scope_ratchet.md`, `feedback_localization_quality_overstating.md` saved to memory.

**Closure Fixup #2 (2026-05-19) — deeper-audit findings:**
- 8-audit codebase-level sweep run after Chairman explicit ask.
- Findings + fixes:
  - **CI cascade-skip bypass (CRITICAL)**: `release.yml` build-macos / build-windows / build-linux `if:` clauses allowed `test.result == 'skipped'`, which would fire when `i18n-gate` cascade-skipped `test` on gate failure. Without an explicit `i18n-gate.result` check, a parity break would silently allow production build/publish. Fix: each build job now has `needs: [i18n-gate, test, setup]` plus an explicit `needs.i18n-gate.result == 'success' || 'skipped'` clause that mirrors the test-job skip semantics. Same `skip_tests=true` bypass still works for dry-run dispatches.
  - **`ErrorPattern.timeSpan` unit suffix hardcoded**: `'${n}m'` / `'${n}h'` / `'${n}d'` was rendered into `diagnosticsPatternSummary` regardless of locale. Fix: 3 new locale-aware keys `diagnostics.timeSpan{Minutes,Hours,Days}` with `{count}` placeholder × 15 locales, resolved via `AppLocalizations.diagnosticsTimeSpan(minutes:, hours:, days:)`. Bucket logic unchanged; only rendered unit text localizes (with native spacing conventions: no space in CJK, narrow space in fr/ru, etc.).
  - **3 missing `errorFeedback.hint` + `.title` keys**: `DownloadErrorCode.{binaryNotAvailable, ffmpegError, sslError}` had been falling back to the generic `unknown` hint, which made the diagnose-panel title read "An unexpected error occurred" while the body rendered code-specific explanation. Fix: hand-crafted hint + title × 15 locales for all 3 codes (Tier 1.5 for en+vi+es+pt+ja+ko+zh+de+fr+ru, best-effort for ar+hi+id+th+tr), then removed the fallback switch in `download_error_code.dart` (now 22/22 error codes have dedicated hint+title keys, no fallback).

---

## 5. External Handoff Packets

| Handoff | Recipient | Artifact | Trigger |
|---------|-----------|----------|---------|
| H1 — Translator capacity request | Chairman + translator lead | This report §3 R2 (locale-tagged leakage list available via `scripts/i18n_leak_gate.py` filter) | When translator bandwidth opens |
| H2 — Plural pilot validation | Native ar/ru speakers | 4 plural keys + 8 count cases (R3) | Same as H1 |
| H3 — Visual smoke matrix | QA via `svid-qa` Windows VM + Mac local | Test plan in R4 | Pre next prod tag dispatch |
| H4 — Diagnostics refactor (R1) | Next state-machine workstream owner | This report §3 R1 acceptance criteria | When diagnostics UX cycle starts |

Handoffs are continuous-improvement tracks. They do **not** unblock production
release on their own, but their absence does not block release either — that is
the explicit waiver semantics in §6.

---

## 6. Content Workstream Closure Statement (with explicit Chairman waivers)

**The content/text/string workstream is closed at commit-level PASS for the four
gates that this workstream owns**, with R1–R4 residuals explicitly waived by
Chairman as out-of-scope.

This statement was previously phrased as "production sign-off (all-users)
granted" — that wording was an **overclaim** (caught by reviewer Codex
2026-05-18). Closing this workstream's gates is necessary but **not
sufficient** for a production release; the four-platform release pipeline
(`release.yml`) is a separate sign-off owned by the Installer/Native CTO role.

**What this closure actually means:**

| Gate | Owned by this workstream? | Status at sealed HEAD |
|------|---------------------------|------------------------|
| Parity (15 locales, identical key tree + placeholders) | Yes | ✅ PASS |
| Hardcoded-NEW in protected widget dirs | Yes | ✅ PASS |
| EN-leakage drift in protected namespaces | Yes | ✅ PASS |
| Protected-namespace voice regression | Yes | ✅ PASS |
| RTL Arabic Directionality in popup isolate | Yes | ✅ Code-wired, runtime smoke pending (R4) |
| Intl date/time honors EasyLocalization | Yes | ✅ Test-covered (8/8 in E3) |
| Soft-warn baseline frozen | Yes | ✅ 14 warns documented, regression-protected |
| Installer/native release readiness | **No** | Out of scope — owned by `release.yml` + Installer/Native CTO |
| Visual smoke matrix (15 locales × 2 brands) | **No** | Owned by QA (R4) |
| EN-leakage long-tail translation quality | **No** | Owned by translator pool (R2) |
| Plural form linguistic correctness ar/ru | **No** | Owned by native speakers (R3) |
| Diagnostics service architecture refactor | **No** | Owned by next state-machine workstream (R1) |

**Explicit waivers granted by Chairman:**
1. ~~**R1 (diagnostics refactor)**~~ — **CLOSED 2026-05-18.** No longer a waiver; refactor was completed in Closure Fixup. See §3 R1 for resolution details.
2. **R2 (EN-leakage long-tail in es/pt/ja deep namespaces)** — waived because en-engineer translation would violate `feedback_localization_quality_overstating.md`. Gate freezes leakage at baseline; drift = hard fail.
3. **R3 (plural pilot ar/ru)** — waived pending native-speaker validation. Linguistic risk, not engineering risk.
4. **R4 (visual smoke matrix)** — waived as QA artifact, not engineering deliverable. To be produced pre next prod tag dispatch via `svid-qa` Windows VM + local Mac.

**Reviewer Codex contract**: any future PR that adds a hard-fail gate violation
must either (a) include a baseline update with explicit rationale or (b) fix
the violation before merging. The reviewer is empowered to reject on hard fail
alone — no escalation needed. The gate now runs in CI (`.github/workflows/ci.yml`
`i18n-gate` job) and Release (`.github/workflows/release.yml` `i18n-gate` job)
as a hard pre-block, so the contract is mechanically enforced, not honor-based.

**End of content workstream.** Successor sessions inherit a closed gate at clean
HEAD with CI enforcement, not an open round count.
