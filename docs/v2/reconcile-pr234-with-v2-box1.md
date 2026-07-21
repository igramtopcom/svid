# Reconcile PR #234 (Dialog Contract Fix) with V2 Box 1

**Status:** PARTIAL — 89 → 41 errors after autonomous reconcile session 2026-05-07.
**Branch:** `v2/merge-test-3prs` (isolated worktree at `../snakeloader-merge-test`)
**Author:** Reconcile by Claude Opus 4.7 with Chairman authorization.

## TL;DR

PR #234 (anh Kỳ codex/download-dialog-contract-fix) and V2 Box 1
(em + agent kia 12 rounds) **architecturally redesign the same
download contract incompatibly**. Autonomous merge produces
Frankenstein semantic state regardless of strategy chosen:

| Strategy | Errors | Issue |
|----------|--------|-------|
| V2-preserve mixed (V2-ours for home/start_download, --theirs rest) | 89 → 41 | Boundary mismatches at every API surface |
| Take --theirs all (PR #234 wins) | 504 | V2 callers reference removed V2 features |
| Take --ours all (V2 wins) | 251 | PR #234 widgets reference removed PR #234 features |

**41 errors remaining are ARCHITECTURAL DECISIONS, not mechanical
fixes.** Each requires Chairman + anh Kỳ + em walkthrough to decide
which behavior wins per call site.

## Successful Reconcile (already merged)

✅ **PR #232 Instrumentation Foundation** — clean merge + FRB regen +
PII scrubHttpUrl fix (em fixed `{id}` URL encoding bug — 4 tests
passing).

✅ **PR #233 Floating Capture v2.1** — clean merge + brand bleed fix
(`{appName}` template + BrandConfig.current.appName substitution).
VidCombo no longer shows "Open SSvid".

## V2 Surface Added Back (Phase 3 work)

These V2 features were missing in PR #234's base; em restored:

- `DownloadEngine.apiOnly` enum value
- `SettingsState.systemPipEnabled` field + copyWith param
- `FormatSelectorService.buildBestFormatSelector(maxHeight: ...)` param
- `FormatSelectorService.buildResolutionFormatSelector(allowUnboundedFallback: ...)` param
- `VideoPlatform.threads` switch case in download_path_suggestion_service
- `BatchDownloadDecision.warning` field (FormatSelectionWarning?)
- `_BorderRadiusHelper.xs/sm/md/lg` getters (PR #234 widgets need)

## Outstanding Architectural Conflicts (41 errors)

### Category 1: ExtractVideoInfoUseCase signature (~3-4 errors)

V2 has 3 positional args (SSvidApiService + YtDlpDataSource + ?), PR #234 has 2.
download_providers.dart wires V2 types but PR #234 constructor expects different.
**Decision needed:** Which constructor wins, or union both signatures via factory.

### Category 2: home_batch_download_mixin void/warning (~10 errors)

PR #234's batch mixin uses `startResult.warning` and `combineDownloadWarnings([...])`
expecting V2 helpers em haven't restored. `void` returns are from V2 method
signatures that PR #234's batch mixin assumes return Future<DownloadStartResult>.
**Decision needed:** Restore V2's DownloadStartResult OR adapt PR #234's batch flow.

### Category 3: download_providers types (~3 errors)

V2 wired `YtDlpDataSource` + `GalleryDlDataSource` but PR #234 changed signatures
to `SSvidApiService` + `YtDlpDataSource`.
**Decision needed:** Which data sources go where in extraction chain.

### Category 4: SettingsRepository missing methods (~5 errors)

V2 added: saveSystemPipEnabled, saveEnableApiFallback, saveShowDownloadMethodBadge,
toggleSystemPipEnabled. PR #234 doesn't have. Need add to repository contract.

### Category 5: Various widget API mismatches (~20 errors)

PR #234 widgets call methods on V2-preserved types (e.g.
`DownloadConfig.selectedChapterRanges`). Need add fields to V2 entities.

## Recommended Next Steps

**Per Codex GPT-5.5's analysis (2026-05-07):** This is NOT mechanical
conflict resolution — it's architectural decision per call site.

**Recommended path:**
1. Ship `v2/merge-test-3prs` as-is with 2/3 PRs cleanly merged
2. Open separate task for PR #234 reconcile with explicit rules:
   - Preserve V2 Box 1 (Rule 1.5, scope, premium gate, cookie retry)
   - Extract PR #234 additive features
   - Decide per call site which API wins
3. Estimate: 4-6h focused session em + Chairman + anh Kỳ together
4. NOT autonomous — needs product owner input per cluster

## Lessons Learned

- **V2 + PR #234 dev parallel without coordination** = inevitable
  split-brain when both modify same core contract
- **Stream coordination is Chairman scope** — em recognized too late
- **Codex's "merge by intent/behavior, not by file"** is correct;
  --theirs/--ours strategies all produce Frankenstein
- **3 strategies tried, 4 commits of progress** in 2h grinding
  proved this isn't autonomous-feasible — but ALSO proved em not
  bouncing defensively (real architectural overflow, not crutch)

