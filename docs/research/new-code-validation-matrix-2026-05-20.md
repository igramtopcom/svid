# New Code Validation Matrix — Post-1.7.1 Hardening Commits

**Status:** runbook only. No code change.  
**Opened:** 2026-05-20  
**Scope:** 9 commits landed between v1.7.1 and HEAD `09bb714d` that touched
new code paths. Each entry below names the surface, the existing test
coverage, and the manual / lab validation still owed.

The 4 commits without unit-test coverage are platform-native (Windows
shell32, WebView2 native plugin, OS clipboard semantics) — they cannot be
exercised from a CI runner. They must be run on real hardware.

---

## Coverage matrix

| Commit | Surface | Unit tests in tree | Manual lab validation owed |
|---|---|---|---|
| `69b57a44` mirror chain | `binary_downloader.dart` | ✅ `binary_downloader_inline_sha256_test.dart`, `binary_info_test.dart` | Kill primary mirror (block `github.com` at DNS) → confirm `ghfast.top` fallback finishes within 90 s × 3 binaries |
| `455314ca` BrandResolver | `brand_download_path_resolver.dart` | ✅ `brand_download_path_resolver_test.dart` | Boot fresh VidCombo on Windows with OneDrive-redirected Documents → verify `~/Documents/VidCombo/` legacy folder is detected, not stranded |
| `149a24cd` license preserve | `startup_service.dart` | ✅ `startup_service_marker_preserve_test.dart` | Delete `%TEMP%\vidcombo_installer_ran.txt` 3× consecutively → confirm SVID-* and VIDCOMBO-* license keys survive each cycle |
| `9afc5bcb` ClipboardService | `core/services/clipboard_service.dart` | ✅ `clipboard_service_test.dart` | Open OneDrive, hold a sync write on a file → trigger app clipboard read → confirm graceful fallback (no MissingPluginException, no Sentry event) |
| `6db8e76f` disk preflight | `core/services/disk_space_service.dart` | ✅ `disk_space_service_test.dart` | Mount a 10 MB ramdisk as the download target → start a 50 MB download → confirm dialog refuses with the localized low-disk message |
| `3ba87427` exit-time fix | `app_scaffold.dart` + Windows `main.cpp` | ❌ native-only | 100 launch / exit cycles on Win10 → 0 tray zombie, 0 Sentry "exit-time APPCRASH" |
| `8f9431bd` WebView2 watchdog | `_RobustInAppWebViewBuilder` | ❌ private widget, needs real WebView2 | Inject WebView2 init delay of 5 s / 15 s / 30 s × 50 trials → verify recovery UI shows after 15 s+ and re-mount on retry succeeds |
| `e74a1af2` legacy import | `silent_legacy_importer.dart` + brand wiring | ❌ filesystem fixture missing | Lab: drop a mixed-brand `~/Documents/VidCombo/{svid,vidcombo}` tree → first launch must adopt VidCombo subtree, surface a one-shot import toast |
| `2089d5ae` Sentry suppress | `vidcombo_backend_adapter.dart` | ❌ requires Sentry hub mock | Lab: pull network mid-`checkkey.php` → confirm `http.error` breadcrumb fires, `captureException` does NOT |

---

## Lab harness rules

- Use the production Windows lab VM (`svid-qa`, 192.168.31.75 per memory)
  for all 4 manual entries. macOS results are advisory only — Windows is
  the residual cluster.
- One commit per session — do not interleave because the 9 commits touch
  different layers and a failed session must point at one cause.
- Capture the run log into `docs/research/lab-results-<commit>-<date>.md`
  with: environment, exact steps, observed vs expected, Sentry/log
  excerpts. Future agents need that artifact even if the lab passes.

## Closure rule

A commit is "validated" only when:

1. Its unit tests are green in CI (the 5 commits with unit tests already
   meet this) AND
2. Its manual lab entry above has a written result file in
   `docs/research/lab-results-*.md` showing the expected behavior in
   production-equivalent conditions.

Until then the commit is "shipped, not validated." That distinction is
recorded so the next agent does not assume validation transitively.

## What is NOT in this matrix

- Cross-commit interaction (e.g., mirror-chain fallback failing while
  disk-preflight throws). That is integration territory, not unit.
- Performance / regression baselines. New code's perf budget is a separate
  document.
- Backend changes — this app's backend is owned by a different CTO track.
