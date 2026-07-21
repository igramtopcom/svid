# Instrumentation Foundation Plan

Plan for the three foundation items identified in the Sentry instrumentation audit. These are the "build the floor before you put up walls" pieces — they affect how all subsequent instrumentation work gets done, so getting the API right matters more than speed.

**Context:** Audit found 9/494 Dart files using `errorReporter`, ~120-150 files with silent `try/catch` (rough count from `grep`; includes some generated `.g.dart` / `.freezed.dart` noise — verify before sizing migration PRs). Sentry SDK is well-configured; the gap is breadth of coverage. See `error_reporter_service.dart` for the existing reporter contract.

**Estimated total effort:** ~3-4 dev days for the three foundation items, then incremental migration over 2-4 weeks (scales with domain size — `core/binaries/` is 4 files, `features/downloads/` is 98).

> **⚠️ This plan does NOT fix the original motivating bug** (`dcomp.dll` crash on sleep, identified during audit). That fix requires a separate item: hook `WM_POWERBROADCAST` in `windows/runner/flutter_window.cpp` and emit power-state breadcrumbs. Estimated ~4 hours, **must run after** Item A so it can use `instrumentedAsync` / `safeCaptureException` for native callbacks. Tracked as audit Item #3 — not in this plan because it doesn't propagate API decisions, and bundling it would delay the foundation.

---

## Item A — `instrumentedAsync<T>()` helper + silent-catch migration

The helper that lets us go from 9 → ~150 instrumented files without writing 150× the same boilerplate. Designing this wrong means every future caller has to remember 5 things; designing it right means call sites become one-liners.

### Goals

1. Replace silent `try/catch` swallows with a single wrapper that always reports to Sentry but lets caller decide whether to swallow, rethrow, or fall back.
2. Auto-inject breadcrumb on entry (optional, off by default) and on failure, with a stable `category` derived from the `op` argument.
3. Tag the captured event itself with `op` and `attributes` — **only** the event captured by `instrumentedAsync`'s own catch. Do NOT attempt to tag exceptions that bubble up from deeper code (see Design D7 below).
4. Match the existing `Result<T>` and `safeBreadcrumb()` style — no new paradigm.
5. Survive a broken reporter (same contract as `safeBreadcrumb`: telemetry must not crash the app).
6. Ship `safeCaptureException()` alongside as a peer to `safeBreadcrumb()` — replacing direct `errorReporter.captureException(...)` calls at sites that already have an exception in hand and don't need block-wrapping.

### Prerequisite — extend `ErrorReporterService` contract

The current `captureException(exception, {stackTrace, context})` only accepts a single `context: String` that `SentryErrorReporter` maps to a tag. `instrumentedAsync` needs to pass `op` + arbitrary `attributes` into the captured event with per-capture scoping (see D7).

**Chosen approach:** add a new method `captureExceptionWithScope` to `ErrorReporterService`. Existing `captureException` call sites stay unchanged. `instrumentedAsync` and any future scope-aware caller uses the new method.

**Signature** (decide concrete `ScopeCallback` shape during impl based on test ergonomics):

```dart
typedef ScopeCallback = void Function(Scope scope);

// In ErrorReporterService:
Future<void> captureExceptionWithScope(
  Object exception,
  ScopeCallback configureScope,
  Map<String, Object?> backendMetadata, {
  StackTrace? stackTrace,
});
```

The `backendMetadata` parameter is the same `op` + `attributes` data the caller used to build `configureScope`, supplied separately so the implementation never has to re-invoke the callback to harvest scope state. Direct callers (anyone using `captureExceptionWithScope` outside `instrumentedAsync`) must keep the two arguments consistent — that's the contract.

The `Scope` type is from `sentry_flutter`; introducing it into the abstract interface couples it to that SDK. Acceptable trade-off — we already depend on it transitively. Alternative: define a lightweight `CaptureScope` interface in our service layer that wraps Sentry's `Scope`. Decide during impl based on whether tests need to construct fake scopes.

**All three implementers must be updated, not just one. Two of them have non-trivial bodies, NOT empty no-ops:**

  1. `SentryErrorReporter.captureExceptionWithScope` — forwards to `Sentry.captureException(exception, stackTrace: stackTrace, withScope: configureScope)`. **Must also call `_submitCrashToBackend` for parity with `captureException`** — otherwise `instrumentedAsync` reports to Sentry but silently stops forwarding to the SSvid backend, breaking the dual-reporting contract that `SentryErrorReporter.captureException` provides at line 97 of `sentry_error_reporter.dart`.

  **Critical: do NOT extract backend metadata by replaying `configureScope`.** An earlier draft proposed running the callback against a "capturing fake scope" to harvest tags/extras for the backend payload, then passing the same callback to Sentry's `withScope`. That invokes the user's callback twice — fine for pure side-effect-free callbacks but unsafe in general (counters, timestamps, throws, or future scope methods we don't fake correctly all diverge).

  Correct design: the *instrumentation helper* (`instrumentedAsync` in Item A) is the only thing that constructs scope data, and it builds both the Sentry-side `configureScope` callback **and** the backend-side `Map<String, Object?> scopeMetadata` from the same already-scrubbed `op` + `attributes` source. It then calls a 4-param method on the reporter:

  ```dart
  // ErrorReporterService:
  Future<void> captureExceptionWithScope(
    Object exception,
    ScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {  // built from same source as configureScope
    StackTrace? stackTrace,
  });
  ```

  `SentryErrorReporter.captureExceptionWithScope` passes `configureScope` to Sentry **once**, and forwards `backendMetadata` to the shared helper that submits to the SSvid backend. Callback runs at most once. Direct callers (i.e. anyone using `captureExceptionWithScope` outside `instrumentedAsync`) are responsible for keeping the two arguments consistent — document this as the contract.

  Refactor existing `_submitCrashToBackend` into a private helper that takes `(exception, stackTrace, context, scopeMetadata)` and is called by both `captureException` (passing `scopeMetadata: const {}`) and `captureExceptionWithScope` (passing the caller-provided map).

  2. **`NoOpErrorReporter` (public class in `lib/core/services/noop_error_reporter.dart`)** — used as the **runtime fallback when Sentry DSN is not configured** (see `main.dart:58-62`). Its existing `captureException` at line 39 forwards to `_submitCrashToBackend` so production health monitoring works even without Sentry. **`captureExceptionWithScope` MUST also forward to backend** — same parity requirement as `SentryErrorReporter`. Otherwise users on builds without a Sentry DSN lose backend crash visibility for the new code path. Implement by extracting the same shared private helper used by the existing `captureException` and pass the **caller-provided `backendMetadata`** map into it. **Do NOT replay `configureScope`** to extract metadata — same callback-purity reason as `SentryErrorReporter`. Since `NoOp` doesn't talk to Sentry, `configureScope` is silently ignored by this implementation; only `backendMetadata` is consumed.

  3. **`_NoOpErrorReporter` (private class in `lib/core/services/error_reporter_service.dart:75`)** — this one IS a true empty no-op. It's the test-only default for `errorReporterServiceProvider` so tests don't need to override the provider explicitly. No backend forwarding needed because it never runs in production.

**Pitfall to avoid:** confusing the public `NoOpErrorReporter` (production fallback, forwards to backend) with the private `_NoOpErrorReporter` (test default, true no-op). The names are nearly identical and the audit-fixed earlier draft conflated them. Both files must be edited; verify each by reading line 32 of `noop_error_reporter.dart` (current `captureException` body) before treating either class as a no-op.

This must land in the Item A foundation PR, before `instrumentedAsync` itself.

### Non-goals

- Not replacing `Result<T>` or `runCatching` — those handle the *control flow*, this handles the *observability*. The two compose.
- Not auto-retrying. Retry logic stays in `circuit_breaker_service.dart` and per-domain code.
- Not building distributed tracing here. That's Item C in the broader audit (Sentry transactions, separate effort).

### Design decisions

#### D1. Wrapper signature: explicit fallback over implicit swallow

```dart
Future<T> instrumentedAsync<T>(
  String operation,                          // e.g. "ytdlp.extract_info"
  Future<T> Function() block, {
  Map<String, Object?>? attributes,          // tags on captured exceptions
  Map<String, Object?>? entryBreadcrumbData, // optional entry breadcrumb
  T Function(Object error, StackTrace stack)? onError,  // fallback value
  bool rethrowAfterReport = true,
  bool emitEntryBreadcrumb = false,          // most call sites: off (noise)
  ErrorReporterService? reporter,            // injected; falls back to global
});
```

**Why explicit `onError`:** Three behaviors need to be possible at the call site:
  1. *Report and rethrow* — most code paths (`rethrowAfterReport: true`, no `onError`)
  2. *Report and swallow with default* — fire-and-forget paths (`onError: (_, __) => fallback`)
  3. *Report and convert to Result* — boundary code (caller wraps in `runCatching`)

Default is "rethrow after report" — matches Dart's default exception behavior, only suppresses if caller explicitly opts in. Avoids the worst failure mode where helper accidentally hides a fatal bug.

**Combination guard** — drop the nullable-fallback magic. Always require `onError` when `rethrowAfterReport: false`. Implementation asserts at runtime: if caller passes `rethrowAfterReport: false` without `onError`, throw `ArgumentError` immediately, regardless of T. Forces explicit fallback semantics; eliminates the brittle "is T nullable" runtime check.

**Why `attributes`, not `data`:** `data` is overloaded in Sentry SDK (breadcrumb data vs. event extra vs. tag). `attributes` is unambiguous. Implementation maps short string-ish values to `setTag` (searchable, dashboard-aggregatable) and longer / non-string values to `setExtra` (per-event blob). Threshold to be calibrated during impl against Sentry SDK's actual tag value limit — verify don't hardcode without checking the SDK source.

**Why optional `entryBreadcrumb`:** A boot path that calls `instrumentedAsync('foo')` 80 times spams the breadcrumb buffer (default 100). Off by default; turn on for high-value boundaries (license check, download start, payment).

#### D2. `operation` is a string namespace, not enum

Convention: `domain.action`, snake_case. Examples:
- `ytdlp.extract_info`
- `ytdlp.download_video`
- `backend.submit_crash`
- `license.activate`
- `webview.load_url`

Stored as Sentry tag `op` (not `operation` — short keys aggregate better in Sentry UI). On failure, becomes the breadcrumb category too.

**Rejected:** typed enum / sealed class. Adds a registration step; new instrumentation at a fresh call site needs zero ceremony.

#### D3. Stack-walk to derive `op` automatically? **No.**

Considered using `StackTrace.current` to auto-tag with file:line. Rejected:
- Release builds have minified stack traces — would tag with garbage.
- `StackTrace.current` allocation on every call is non-zero cost on hot paths (download progress callbacks).
- Forces the human to think "what is this operation called" — that label is what dev reads in Sentry, garbage labels = garbage UX.

#### D4. Sync version

Add `instrumentedSync<T>` mirroring `runCatchingSync`. Same contract minus async. Some call sites (file I/O via `File.readAsStringSync`, JSON parse) are sync.

#### D5. Composition with `runCatching` and `Result<T>`

Both compose cleanly:

```dart
// Boundary code — converts to Result, instruments along the way
Future<Result<VideoInfo>> extractInfo(String url) =>
    runCatching(() => instrumentedAsync(
          'ytdlp.extract_info',
          () => _native.ytdlpExtractInfo(url: url),
          attributes: {'url_host': Uri.parse(url).host},
        ));
```

`instrumentedAsync` rethrows by default → `runCatching` catches → `Result.failure`. Sentry already has the report. Zero double-reporting because rethrow happens *after* `Sentry.captureException`.

#### D6. Argument scrubbing

`attributes` go through PII scrubbing before being attached. Caller doesn't have to remember not to pass URLs as raw strings.

**Scrubber extension required.** Current `piiScrubber` only walks `event.message`, `event.exceptions`, and `event.breadcrumbs` — it does not visit `tags`, `extras`, `request.data`, `user`, `contexts`, or `fingerprints`. Item A and Item B both populate `tags` and `extras`; without extending the walker, attributes containing URLs/paths/license keys will reach Sentry unredacted.

Foundation PR adds:
  - A standalone `String scrubString(String input)` for direct attribute scrubbing at attach time (preferred — scrubs at source).
  - Extend `piiScrubber(SentryEvent)` to also walk `tags`, `extras`, `request`, `user`, `contexts` so anything we miss at attach time gets a second pass via `beforeSend`.
  - Extend regex set: 32-char hex license keys, UUIDs, JWTs, Stripe-style ids (`sk_*`, `pk_*`), API key prefix `snk_*`, email addresses.

These regex additions get unit-tested in `pii_scrubber_test.dart` with positive (must redact) and negative (must NOT redact something that looks similar but isn't) cases for each pattern.

#### D7. Scope tagging is local, not global

**Anti-pattern to avoid:** Calling `Sentry.configureScope((s) => s.setTag('op', op))` at block entry and clearing on exit. `configureScope` mutates the **global** scope on the current Sentry hub. Two `instrumentedAsync` calls running concurrently (which happens constantly in async code) will trample each other's tags, and exceptions bubbling up between the entry/exit pair pick up whichever tag won the race.

**What we actually do:** Tag only the event captured *by `instrumentedAsync`'s own catch block*, via the 4-param contract:

```dart
await errorReporter.captureExceptionWithScope(
  e,
  (scope) => scope.setTag('op', op),  // also sets attribute tags/extras
  {'op': op, ...scrubbedAttributes},  // same data, for backend metadata
  stackTrace: stack,
);
```

(See Prerequisite section above for full contract.) Internally `SentryErrorReporter` forwards to `Sentry.captureException(..., withScope: configureScope)` — per-capture scope, no leak — and forwards `backendMetadata` to the SSvid backend via the shared `_dispatchCrashToBackend` helper.

**Consequence:** an exception thrown from 3 calls deep that escapes `instrumentedAsync` (because we rethrow) will hit the nearest enclosing catcher — `FlutterError.onError` or `PlatformDispatcher.onError` in `main.dart` — with NO `op` tag. That's the correct behavior; the deeper call could have its own `instrumentedAsync` if it wanted a tag. We do not pretend to provide tagging-by-magic across nested calls.

### File plan

New file: `lib/core/services/instrumentation.dart`

```dart
// Public API:
//   Future<T> instrumentedAsync<T>(...)
//   T instrumentedSync<T>(...)
//   Future<void> safeCaptureException(reporter, exception,
//                                     {stackTrace, scopeConfig, backendMetadata})
//
// Depends on:
//   - error_reporter_service.dart (ErrorReporterService, safeBreadcrumb,
//     captureExceptionWithScope contract added in foundation PR)
//   - pii_scrubber.dart (extend with attribute scrubbing helper + new PII patterns)
```

(The earlier draft claimed "imports nothing UI-related." Removed — `error_reporter_service.dart` already imports `package:flutter/widgets.dart` (for `NavigatorObserver`) and `package:flutter_riverpod/flutter_riverpod.dart`, so anything depending on it is transitively bound to Flutter. The purity claim was wrong.)

`safeCaptureException` is **async** — `ErrorReporterService.captureException` returns `Future<void>`, so a sync wrapper that doesn't `await` would silently miss async failures inside the reporter (rejected futures, network errors during capture). Signature:

```dart
Future<void> safeCaptureException(
  ErrorReporterService? reporter,
  Object exception, {
  StackTrace? stackTrace,
  ScopeCallback? scopeConfig,
  Map<String, Object?>? backendMetadata,  // required when scopeConfig != null
}) async {
  if (reporter == null) return;
  try {
    if (scopeConfig != null) {
      // Both scopeConfig and backendMetadata are supplied by caller and must
      // be consistent — caller built them from the same source data. Same
      // contract as instrumentedAsync's internal call.
      assert(backendMetadata != null,
          'safeCaptureException: scopeConfig requires backendMetadata');
      await reporter.captureExceptionWithScope(
        exception,
        scopeConfig,
        backendMetadata ?? const {},
        stackTrace: stackTrace,
      );
    } else {
      await reporter.captureException(exception, stackTrace: stackTrace);
    }
  } catch (_) {
    // Silent — same contract as safeBreadcrumb.
  }
}
```

Caller-side contract: if you pass `scopeConfig`, you must also pass `backendMetadata` derived from the same source data. The wrapper enforces this with an `assert` (debug builds) and a defensive fallback to `const {}` (release builds — degrades gracefully rather than throwing). Most call sites won't use `scopeConfig` at all; they're sites that already have an exception and just need safe forwarding without scope.

Test file: `test/core/services/instrumentation_test.dart`

Test cases:
1. Block returns value → returned through, no Sentry event captured.
2. Block throws (sync `throw`), `rethrowAfterReport: true` → `captureExceptionWithScope` called once, exception rethrown unchanged.
3. Block returns rejected `Future` (async failure) → reported and rethrown with original stack preserved (use `Error.throwWithStackTrace` semantics or `Future.error(e, stack)`).
4. Block throws, `rethrowAfterReport: false`, no `onError` → throws `ArgumentError` immediately (caller misconfigured).
5. Block throws, `onError` provided → `onError` result returned, Sentry captured.
6. Block throws, `onError` itself throws → original block exception rethrown (the `onError` exception is reported as an additional event via `safeCaptureException`, never replaces the original failure).
7. Reporter's `captureExceptionWithScope` throws → wrapper still rethrows the original block exception. The reporter failure does NOT mask the real bug.
8. Block throws → `op` tag set on captured event via `withScope` (per-capture, NOT global scope — see D7).
9. Two concurrent `instrumentedAsync` calls with different `op` values both throw → each captured event has its own `op` tag, no cross-contamination.
10. PII in attribute (URL, license key, email) → scrubbed in the captured event.
11. Reporter throws inside `addBreadcrumb` → wrapper still completes block (using existing `safeBreadcrumb` semantics).
12. Long `attributes` value → routed to `setExtra` not `setTag` (threshold determined during impl, asserted in test against actual chosen value).
13. `Error` (not `Exception`) thrown inside block → still captured (matches `runCatching` behavior).
14. `safeCaptureException` with null reporter → no-op, no throw, returns immediately.
15. `safeCaptureException` with reporter whose `captureException` returns rejected Future → swallowed silently, caller unaffected (proves async safety).
16. `safeCaptureException` with `scopeConfig` + `backendMetadata` provided → forwards to `captureExceptionWithScope` with the 4-param contract; scope callback invoked once; backend metadata passed through verbatim.
17. `safeCaptureException` with `scopeConfig` provided but `backendMetadata: null` → in debug builds, `assert` fires; in release builds, helper falls back to empty map and forwards (defensive degradation).

### Migration strategy for the silent-catch sites

Foundation PR ships first. Migration is incremental, **2-4 weeks elapsed time** depending on domain sizes (small domains like `core/binaries/` are 4 files / half a day; `features/downloads/` is 98 files / 3-5 days). Don't try to do everything in one PR.

First step before any migration PR: re-run the silent-catch grep excluding `*.g.dart`, `*.freezed.dart`, and `test/` to get a real number — the audit's 147 figure includes generated files. Real number is likely 100-130.

**Phase 1 (foundation PR, 1 day):** Add `instrumentation.dart` + tests + 5-10 hand-picked call sites to validate the API works end-to-end. Pick sites from different layers:
  - 1 in `ytdlp_datasource.dart` (subprocess boundary — high signal)
  - 1 in `backend_service.dart` (HTTP boundary — Item B will replace this, but exercises pattern)
  - 1 in `player_manager.dart` (native plugin boundary)
  - 1 in `process_helper.dart` (subprocess wrapper — propagates to many callers)
  - 1 in any `features/premium/` flow (revenue path)

**Phase 2 (per-domain PRs, scaled by file count):** One PR per top-level domain. Sized roughly:
  - `core/binaries/` (4 files) — half a day
  - `core/auth/` (cookie extractor, login dialog) — half a day
  - `core/database/` (Drift wrappers) — half a day
  - `core/services/` (the unstuffed ones — circuit_breaker, proxy_rotation, hardware_fingerprint, opensubtitles, ticket_poll) — 1 day
  - `features/premium/` (22 files — split into 2-3 sub-PRs: payment, license, members) — 2-3 days total
  - `features/downloads/` (98 files — biggest; split across 3-4 sub-PRs by feature area) — 3-5 days total
  - `features/player/` (31 files) — 1-2 days
  - `features/browser/` (36 files) — 1-2 days
  - `features/youtube_*` (3 modules combined) — 1-2 days

**Triage rule per silent catch:** Three categories, decide per site:
  1. *Genuine no-op* (e.g. cleanup that "best-effort" deletes a temp file) — leave silent, but add inline comment `// instrumentation: intentional silent — best-effort cleanup, never user-visible`.
  2. *Soft error* (operation can fall back) — replace with `instrumentedAsync(..., onError: (e, s) => fallbackValue)`.
  3. *Hard error swallowed by mistake* — replace with `instrumentedAsync(...)` (default rethrow). If a test breaks, it was hiding a bug.

Migration is deliberately **not bulk-automated.** Sed-replacing 147 files would file-flip category #3 → #2 silently. A human has to read each catch.

### Definition of done

- `ErrorReporterService` interface extended with `captureExceptionWithScope` (4-param contract: `exception`, `configureScope`, `backendMetadata`, `{stackTrace}`). All **three** implementers updated: `SentryErrorReporter` (forwards to Sentry + backend), public `NoOpErrorReporter` (forwards to backend, ignores scope callback), private `_NoOpErrorReporter` (true empty no-op for tests). Per pass-3 finding: confusing the public and private NoOps is a real pitfall — verify both files.
- `instrumentation.dart` lands with the 17 unit tests listed above.
- `pii_scrubber.dart` extended to walk `tags`/`extras`/`request`/`user`/`contexts`, plus new regex set (license keys, UUIDs, JWTs, Stripe ids, API keys, emails) with positive + negative tests for each.
- 5-10 hand-picked sites migrated to validate end-to-end.
- One round of Sentry events generated (intentional crash in dev) verifies `op` tag and PII scrubbing visible in dashboard.
- Migration tracker added to `docs/instrumentation-migration-progress.md` listing every silent-catch file with status (todo/migrated/triaged-as-noop). Initial commit populates with `grep` output; subsequent PRs check off entries.

### Open questions for product/lead

- Q1: Should `op` tag namespace include the brand (e.g. `ssvid.ytdlp.extract_info` vs `ytdlp.extract_info`)? **Recommendation:** brand goes in a separate `brand` tag (already covered by `BrandConfig.current`); `op` stays brand-agnostic so cross-brand bug aggregation works.

(Migration sequencing decided in Phase 2 above — per-domain PRs, not a mega-PR.)

---

## Item B — HTTP client interceptor for auto-instrumentation

`BackendClient` already uses Dio with an interceptor list. Adding instrumentation here means **every backend call instantly gets coverage** with zero per-callsite changes. Highest ROI of the three foundation items.

### Goals

1. Auto-emit breadcrumb on every HTTP request: method, scrubbed URL, status, duration.
2. On failure, auto-attach: status code, response body excerpt (scrubbed), request_id (if backend returns one), connection state (online/offline).
3. Cover both `BackendClient` (Dio, X-API-Key auth) **and** `VidComboBackendAdapter` (confirmed raw `http.Client` — see `lib/core/services/vidcombo/vidcombo_backend_adapter.dart` line 4 import; query string at line 51 carries `device_id` and `license_key` as params, must scrub aggressively).
4. Don't double-report: if `BackendService.submitCrash` itself fails, the interceptor must not loop into reporting *the report*. Note: this exclusion applies **only** to crash forwarding, not to user-initiated bug reports — see Self-protection section below.
5. Capture **envelope-level** failures (HTTP 200 but `{success:false}`), not just transport-level errors — see Envelope handling section.

### Non-goals

- Not replacing `LogInterceptor` — it's local-only for dev, leave it be.
- Not building a generic HTTP framework. The interceptor is Dio-specific. If `VidComboBackendAdapter` uses raw `http.Client`, write a thin shared helper that emits the same breadcrumb shape — don't try to abstract HTTP libraries.
- Not caching/deduping breadcrumbs. Default Sentry buffer (100 items) is fine; interceptor is first-write.

### Design decisions

#### D1. Interceptor type: Dio `Interceptor`, registered in `BackendClient` constructor

The constructor already adds `_AuthInterceptor` and `LogInterceptor`. New `_SentryHttpInterceptor` slots in **before** `LogInterceptor` (so logs reflect what was actually instrumented) and **after** `_AuthInterceptor` (so we never breadcrumb a request that auth rejected pre-flight).

#### D2. Breadcrumb category: `http`

Sentry SDK conventionally uses `http` for HTTP breadcrumbs. Sets the right icon in dashboard. Type: `http` (also a Sentry standard).

#### D3. URL scrubbing: extend `pii_scrubber.dart`

The existing scrubber redacts full URLs. For HTTP breadcrumbs we want a route template, not the concrete URL. **Stripping the query string is not enough** — concrete paths embed identifiers: `/tickets/<uuid>`, `/assistant/sessions/<uuid>`, `/users/<id>/license` (see `backend_service.dart` lines 97, 174). Each ID is a privacy-sensitive correlation handle.

New helper:

```dart
/// Scrub a URL for HTTP breadcrumbs to a route template:
///   https://api.ssvid.app/v1/tickets/abc-uuid?key=secret
///   → https://api.ssvid.app/v1/tickets/{id}
///
/// Steps:
///   1. Strip query string entirely.
///   2. Walk path segments; replace any segment matching:
///      - UUID regex (`[0-9a-f-]{32,36}` with hyphen pattern) → `{id}`
///      - Bare 32-char hex (license keys) → `{license}`
///      - Email regex → `{email}`
///      - Stripe-style `sk_*`, `pk_*` → `{stripe_id}`
///      - SSvid API key prefix `snk_*` → `{api_key}`
///      - Long opaque tokens (>20 chars, base64-ish) → `{token}`
///   3. Keep static segments (e.g. `v1`, `tickets`, `crashes`) as-is.
String scrubHttpUrl(Uri uri);
```

Implemented next to existing scrubber regexes. Tests in `pii_scrubber_test.dart`:
  - Static path → unchanged.
  - UUID segment → `{id}`.
  - License key segment → `{license}`.
  - Email in path → `{email}`.
  - Query string with `license_key=...` → stripped entirely.
  - Mixed segments (`/v1/users/abc-uuid/tickets/xyz-uuid`) → `/v1/users/{id}/tickets/{id}`.
  - Real-world: `/tickets/$id` from `BackendService.getTicket` → `/tickets/{id}`.
  - Real-world: VidCombo `?device_id=...&license_key=...` → query stripped, only path remains.

#### D4. Response body excerpt size: 512 bytes, only on error

On 4xx/5xx, attach first 512 bytes of response body to the captured event as `extra['http.response_body_excerpt']`. Run through `_scrub` first. On success: do not attach body (noise + privacy).

512 bytes is enough to see error envelope (`{success: false, error: {code, message}}`) without bloating events.

#### D5. Request ID propagation

Backend returns `X-Request-Id` header (need to confirm during impl — common pattern, may need backend coordination). If present, set as Sentry tag `http.request_id`. Lets dev correlate Sentry event → backend log line.

If backend doesn't return one yet: this is a 1-line backend change, file as a follow-up backend ticket. Don't block this PR.

#### D6. Network state context

On *failure* only, attach `extra['network.online']`. Distinguishes "API down" from "user's wifi dropped".

`NetworkMonitorService.isOnline()` returns `Future<bool>`, not sync. Two viable approaches:
  1. **`await`** inside the Dio interceptor's `onError` (Dio interceptors support async — see existing `_AuthInterceptor` for precedent). Adds one connectivity round-trip on failure path only.
  2. **Cache last-known state** by subscribing to `NetworkMonitorService.onlineStream` from the interceptor constructor and storing the latest value in a field. Sync read in `onError`. No extra latency.

Recommendation: option 2 (cached). Failure paths shouldn't pay extra round-trips, and the cached value is "most recent observed state" which is exactly what we want for the breadcrumb. Subscription disposed when the interceptor is.

### Envelope-level failure capture

`BackendClient._unwrap` (line 147 in `backend_client.dart`) throws `AppException.network` when the HTTP response is 200 but the JSON body has `success: false`. This path **does not go through Dio's `onError`** — it's a synchronous throw in the post-response code, after the interceptor has already let the response through.

The Dio interceptor alone misses this entire failure category — which is the *more interesting* one (backend up, returning structured error envelope). Coverage requires one of:

  1. **Tap `_unwrap` directly:** add a private `_reportEnvelopeError(response, error)` call inside `_unwrap` before throwing. Cleanest. Uses the same `safeCaptureException` helper from Item A. Recommended.
  2. **Add `onResponse` interceptor that inspects the body:** more general but means the interceptor needs to know the envelope shape. Bad layering.

Recommendation: option 1. Pass the reporter into `BackendClient`, call from `_unwrap` on the failure branch, attach the envelope error code/message as `extra`. Document the dual-path nature ("transport failures via interceptor, envelope failures via `_unwrap` tap") in code comments.

**Self-protection must extend to `_unwrap`.** The `_sentryInternal` flag described below stops the *transport interceptor* from looping on `submitCrash` failures — but `_reportEnvelopeError` runs on a separate code path and would loop independently if `submitCrash` returned `{success:false}`. Mitigation: `_reportEnvelopeError` reads `response.requestOptions.extra['_sentryInternal']` and early-returns when set. Same flag, two read sites.

### Retry semantics

`_AuthInterceptor` (line 253 of `backend_client.dart`) catches 401 and re-fetches via `_dio.fetch(opts)` after refreshing auth. This produces **two passes through `_SentryHttpInterceptor`**: original 401 + retry. Define behavior explicitly:

  - Original 401: emit breadcrumb at `warning` level, but **do not** capture as Sentry event (auth refresh is normal flow).
  - Retry attempt: emit breadcrumb at `info` level with tag `http.retry: true`.
  - Retry success: emit breadcrumb `http.retry_succeeded`.
  - Retry failure: capture as event (this is the actual user-visible failure).

Mark requests in retry via `RequestOptions.extra['_isRetry'] = true` set by `_AuthInterceptor` before `_dio.fetch`. New interceptor reads the flag.

Tests:
  - Stale key → 401 → refresh succeeds → retry succeeds → no captured event, two breadcrumbs visible.
  - Stale key → 401 → refresh fails → no retry → captured event with original 401.
  - Stale key → 401 → refresh succeeds → retry returns 500 → captured event with retry's 500, retry breadcrumb visible.

### File plan

Modify: `lib/core/network/backend_client.dart`
- Add `_SentryHttpInterceptor` class in same file (private, file-scoped — same pattern as existing `_AuthInterceptor`).
- Register in `BackendClient` constructor after `_AuthInterceptor`, before `LogInterceptor`.
- **Extend `get`/`post`/`postVoid` signatures** to accept an `Options? options` parameter (Dio idiom). Currently they take only `path`/`data`/`fromJson` (line 41 onwards) — caller has no way to attach metadata. Without this, the self-protection flag for `submitCrash` cannot be applied. Use `Options(extra: {'_sentryInternal': true})` — `RequestOptions.extra` is untyped key/value bag, doesn't reach the wire as headers but does reach interceptors. `extra` not `Options.headers` so we don't leak the marker to backend logs.
- Add `_reportEnvelopeError` private method called from `_unwrap` on `success: false` branch. Reads `response.requestOptions.extra['_sentryInternal']` for self-protection (see Envelope-level failure capture section).
- **Refactor envelope-error throw paths through `_unwrap`.** Current `postVoid` (line 69) and `deleteVoid` (line 99) inline the `success:false` check and throw directly, bypassing `_unwrap`. Without refactor, `_reportEnvelopeError` only catches the `get`/`post`/`delete`/`patch` envelope failures, missing the void variants. Two options:
  - **Option A (preferred):** introduce a `_unwrapVoid(Response)` helper that does the same envelope check + reports + throws, and call it from `postVoid`/`deleteVoid` (and any future `*Void` methods). Keeps the envelope-tap pattern in one place.
  - **Option B:** explicitly tap `_reportEnvelopeError` inside `postVoid` and `deleteVoid`. Acceptable but easy to forget when adding future void methods — option A is more maintainable.

  Pick A unless impl reveals a reason not to. Either way, all four manual-throw sites must be covered before the PR is done.

  **Bit-exact behavior preservation required.** `postVoid` and `deleteVoid` differ from `_unwrap` in two specific ways that callers may already depend on:
   - **Fallback message.** Void variants use `'Request failed'` (line 76, 106 of `backend_client.dart`). `_unwrap` uses `'Unknown error'` (line 148). `_unwrapVoid` MUST keep `'Request failed'`.
   - **`AppException.network.data` field.** `_unwrap` sets `data: error?['code']` to surface the backend error code. Void variants do NOT set `data`. `_unwrapVoid` MUST omit `data` to match existing behavior — adding it would silently change what callers see.

  The only allowed behavior change in `_unwrapVoid` is the addition of `_reportEnvelopeError(response, error)` before throwing. Tests required:
   - `postVoid` against a `{success:false}` response without `error.message` → throws `AppException.network` with message `'Request failed'`, statusCode preserved, `data` is null.
   - `postVoid` against a `{success:false, error:{message:'X'}}` → throws with message `'X'`, `data` is null.
   - Both throw cases also produce a Sentry event (proving `_reportEnvelopeError` ran), with the envelope error code/message in `extras`.
   - Same trio for `deleteVoid`.
- Constructor signature change: add `ErrorReporterService` and `NetworkMonitorService` as **optional named parameters with no-op defaults**, not required. Existing test code that constructs `BackendClient(credentials)` directly continues to compile; production wiring passes the real services.

**Wiring ergonomics — inject at the provider level, NOT through `BackendService`:**

Earlier draft suggested "modify `BackendService` constructor to take `ErrorReporterService`, pass to `BackendClient`." That's backwards: `BackendService` is constructed *with* a `BackendClient`, so the client already exists by the time `BackendService` runs. The reporter has to land in `BackendClient`'s constructor directly, not via `BackendService`.

Correct wiring lives in `lib/core/providers/backend_providers.dart` (or wherever `backendClientProvider` is defined): the provider reads `errorReporterServiceProvider` + `networkMonitorServiceProvider` and constructs `BackendClient(credentials, errorReporter: ..., networkMonitor: ...)`. `BackendService` constructor stays unchanged — it still just takes a `BackendClient`.

Modify: `lib/core/services/pii_scrubber.dart`
- Add `scrubHttpUrl(Uri)` helper.
- Add unit tests for path-keeps / query-strips.

Modify: `lib/core/providers/backend_providers.dart` (or wherever `backendClientProvider` lives)
- Wire `BackendClient` construction with `errorReporterServiceProvider` and `networkMonitorServiceProvider`. **`BackendService` constructor is NOT touched** — earlier draft proposed modifying it, but that's backwards (see "Wiring ergonomics" above). The provider for `BackendClient` is the only place that needs editing.

Wrap: `lib/core/services/vidcombo/vidcombo_backend_adapter.dart`
- Confirmed uses raw `http.Client` (line 4 import). Extract a thin helper `_instrumentedHttpRequest()` in the adapter file that:
  1. Records start time.
  2. Awaits the underlying `_client.send(...)` (or `.get`, `.post`).
  3. On completion, emits the same breadcrumb shape as `_SentryHttpInterceptor` (`category: http`, `data: {method, url, status, duration_ms}`).
  4. On failure, captures via `safeCaptureException` with envelope details.
  5. Runs `scrubHttpUrl(uri)` BEFORE emitting — VidCombo's `?device_id=...&license_key=...` query MUST be stripped (verified at line 51 of adapter).
- Test cases for VidCombo wrapper: query string is never emitted in any breadcrumb, license key never reaches Sentry, network failure emits breadcrumb + captured event.

### Self-protection: only `submitCrash` is internal, NOT `submitBug`

`SentryErrorReporter._submitCrashToBackend` calls `backend.submitCrash`. If that POST fails, the new interceptor would try to capture the failure → which would call `submitCrash` again → loop. Must mark `submitCrash` as internal so the interceptor skips it.

**Critical scoping correction:** `submitBug` is **NOT** internal. Earlier draft said both should be marked — wrong. `submitBug` is user-initiated ("I want to report a bug to support") and its failures are real ops issues that ops genuinely wants to see in Sentry. Excluding it would create a blind spot exactly where coverage matters most.

Mitigation: caller marks the request via `RequestOptions.extra['_sentryInternal'] = true`. Specifically:
  - `BackendService.submitCrash` (and any future *crash forwarding* endpoints) sets this flag.
  - `BackendService.submitBug` does NOT set it — bug submissions get full instrumentation.
  - Interceptor reads `options.extra['_sentryInternal']` and early-returns (no breadcrumb, no capture, no body excerpt) when set.

Why `extra` not header: `RequestOptions.extra` is a Dio-internal key/value bag that interceptors can read but never reaches the wire. Doesn't leak our internal marker as an on-wire header to backend logs.

Document the flag as a contract in `backend_client.dart` so future endpoints classify themselves correctly.

### Layering with Item A: double-coverage is intentional

A call like `BackendService.submitBug(...)` may eventually be wrapped in `instrumentedAsync('backend.submit_bug', ...)` (Item A migration). That's two breadcrumbs for the same request: one with `op: backend.submit_bug` from Item A, one with `category: http` from this interceptor.

This is **intentional, not deduplicated.** The two breadcrumbs answer different questions:
  - Item A breadcrumb says: "intent layer — caller wanted to submit a bug"
  - Item B breadcrumb says: "transport layer — HTTP POST to /bugs returned 503"

In a crash report, dev sees both and can correlate. Deduplicating would force one layer to know about the other; keeping them parallel is simpler and more useful.

### Definition of done

- `_SentryHttpInterceptor` lives in `backend_client.dart` with `_sentryInternal` flag self-protection.
- `_unwrap` taps envelope failures via `_reportEnvelopeError`.
- `BackendClient` `get`/`post`/`postVoid` accept `Options? options`.
- `scrubHttpUrl` lands in `pii_scrubber.dart` with route-template scrubbing + tests for UUID, license key, email, query string.
- VidCombo adapter wrapped with `_instrumentedHttpRequest()` helper, query parameters proven scrubbed via test.
- Retry breadcrumb behavior implemented per spec, with 3 test cases above.
- All `BackendClient` requests emit `http` breadcrumbs verified by manual smoke test (dev mode + Sentry test DSN).
- Smoke test: kill backend, hit `submitBug` (NOT submitCrash), verify Sentry event has `http.status_code`, `http.response_body_excerpt`, `network.online`, `op: backend.submit_bug` (the last comes from Item A composition).
- Smoke test: hit `submitCrash` while backend is down → no Sentry event from the interceptor (loop prevention works).
- Smoke test: backend returns 200 with `{success:false, error:{code:..., message:...}}` → envelope error captured with code/message in extras.

### Open questions

- Q1: Does backend return `X-Request-Id`? (Check Go middleware in `backend/internal/`.) If not: file followup ticket.
- Q2: Does VidCombo PHP backend? Not under our control. Assume no, breadcrumb without `request_id` for VidCombo.

---

## Item C — Rust panic hook + sentry-rust integration

The riskiest of the three because it crosses the FFI boundary. Get it right and Rust panics (which currently surface as opaque FFI errors with no Rust stack) become first-class Sentry events. Get it wrong and Rust panic during shutdown deadlocks the app.

**Estimate calibration:** original "1.5 days" assumed the file-fallback path was a one-liner. After accounting for proper event reconstruction from on-disk panics (D4 below) and async-wrapping the `instrumented` macro (D5), realistic estimate is **2-3 days** for the implementation alone, plus a smoke-test pass that requires generating real panics across the FFI in dev. Worth flagging because Rust+FFI work historically slips on this codebase.

### Goals

1. Capture Rust panics as Sentry events with full Rust backtrace, not just the FFI string Dart sees.
2. Capture `anyhow::Error` chains at FFI boundaries (currently lost when converted to Dart strings).
3. Tag all Rust-originating events with `runtime: rust` so they aggregate separately from Dart events.
4. Survive panic-during-startup (before Dart side is ready) — fall back to writing a panic file to disk that the next launch uploads.

### Non-goals

- Not full distributed tracing across FFI. Out of scope.
- Not replacing `anyhow` with custom error type. The conversion happens at the FFI boundary; internal Rust code stays as-is.
- Not asserting full Tokio task panic coverage. The standard panic hook fires for direct panics, but `tokio::spawn`'d tasks can swallow panics into their `JoinHandle` depending on how the runtime is configured. Treated as a known risk to validate during impl smoke testing (see Q3) — **the plan does not promise** that every Tokio task panic produces a Sentry event.

### Design decisions

#### D1. SDK choice: `sentry` crate, not custom HTTP

Use the official `sentry` crate with the `anyhow` and `panic` integration features (current sentry-rust exposes these as facade features on the `sentry` crate itself; verify exact name during impl). Rejected hand-rolling HTTP because:
- Sentry envelope format changes; SDK tracks it.
- DSN parsing, retry, offline buffering are non-trivial.
- Crate is well-maintained, widely deployed.

#### D2. Init order: pragmatic compromise (chicken-and-egg)

**The chicken-and-egg problem:** the original draft said "init must happen before any FRB work, so a panic during init gets captured" — but also exposed `init_telemetry` *via FRB*. Generated FRB APIs are not callable until `RustLib::init()` completes (see `lib/main.dart:281`). So the function we'd use to init telemetry-before-FRB needs FRB to already be initialized. Dead end.

**What we actually do:** accept that telemetry inits *after* `RustLib::init`. Window of un-instrumented Rust code: from the moment Rust object code loads (dlopen) through `RustLib::init` returning to Dart. This is small (no business logic, just FFI registration) and rarely fails — acceptable blind spot.

```rust
// native/src/telemetry.rs (pseudocode, refine during impl)
use std::sync::OnceLock;

static TELEMETRY: OnceLock<sentry::ClientInitGuard> = OnceLock::new();
static PANIC_HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

pub fn init_telemetry(
    dsn: Option<String>,
    release: String,           // passed from Dart, NOT env!("CARGO_PKG_VERSION") — see D6
    panic_dir: String,         // brand-specific, passed from Dart — see D7
) {
    if let Some(dsn) = dsn {
        let guard = sentry::init((
            dsn,
            sentry::ClientOptions {
                release: Some(release.into()),
                attach_stacktrace: true,
                ..Default::default()
            },
        ));
        // _guard must be held for process lifetime — store in OnceLock.
        let _ = TELEMETRY.set(guard);
    }
    // Idempotent: panic hook installed at most once per process lifetime.
    // Hot restart re-enters init_telemetry but does NOT re-install the hook.
    if PANIC_HOOK_INSTALLED.set(()).is_ok() {
        install_panic_hook(panic_dir);
    }
}
```

**Wiring in Dart `main.dart`:** invoke after `_initRustBridge()` succeeds, before any other FFI call:

```dart
// In _initRustBridge, after RustLib.init and before downloadManagerInit:
if (EnvConfig.isSentryConfigured) {
  try {
    await native.initTelemetry(
      dsn: EnvConfig.sentryDsn,
      release: '${BrandConfig.current.brand.name}@${AppConstants.appVersion}',
      panicDir: await _resolveRustPanicDir(),  // brand-specific, see D7
    );
  } catch (e) {
    appLogger.warning('Rust telemetry init failed (non-critical): $e');
  }
}
```

**Both sides talk to the same Sentry project** (same DSN, single project — see Q1 below).

#### D3. DSN passing: from Dart, not embedded

Don't bake DSN into Rust binary. Keeps brand switching working (one binary serves SSvid + VidCombo, each with its own DSN if we ever split).

#### D6. Release tag source: from Dart, not `CARGO_PKG_VERSION`

Original draft used `env!("CARGO_PKG_VERSION")` for the Rust Sentry release tag. **Wrong** — `native/Cargo.toml` line 3 has `version = "0.1.0"`, which is unrelated to the app's release version (currently `1.3.7+12` per `pubspec.yaml`). Tagging Rust events with `0.1.0` would break release-grouping in Sentry (Rust events from every shipped app version would aggregate together).

**Fix:** Dart passes `${BrandConfig.current.brand.name}@${AppConstants.appVersion}` as the `release` argument to `init_telemetry`. Same string both Dart and Rust use, so events group consistently in Sentry.

#### D7. Panic file path: brand-aware, passed from Dart

Original draft hardcoded `<app_data>/ssvid/rust_panics/`. **Wrong on two counts:**

  1. Multi-brand: VidCombo uses `<app_data>/vidcombo/`, not `<app_data>/ssvid/`. Hardcoding `ssvid` puts panic files in the wrong place for VidCombo users.
  2. Rust on its own has no reliable cross-platform "app data" resolver. Dart side does (`path_provider.getApplicationSupportDirectory`), so resolve there and pass in.

Dart resolves `<applicationSupportDirectory>/<brand_dir>/rust_panics/` (creates if missing) and passes the absolute path to `init_telemetry`. Brand directory comes from `BrandConfig.current`.

#### D4. Panic hook: file fallback

```rust
fn install_panic_hook(panic_dir: PathBuf) {
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        // 1. Write panic file to disk (always, even if Sentry succeeded).
        //    Path: <panic_dir>/<timestamp>_<thread>.json
        //    panic_dir is brand-resolved from Dart side — see D7.
        //    Content: structured JSON — panic message, file:line, captured backtrace,
        //    thread name, app version, optional Tokio task name. JSON (not plain text)
        //    so the Dart side can reconstruct a SentryEvent without re-parsing.
        let _ = write_panic_file(&panic_dir, info);

        // 2. Forward to Sentry (sentry-panic integration handles this).
        prev(info);
    }));
}
```

**On next app launch, the Dart side reconstructs proper events — not just messages.** This is more involved than the original plan implied:

```dart
// In StartupService deferred phase:
for (final file in panicFiles) {
  final json = jsonDecode(await file.readAsString());
  // Build a SentryEvent with a synthetic SentryException whose `stacktrace`
  // is parsed from the Rust backtrace string into SentryStackFrame entries.
  // Without this, the event shows up as plain message text in Sentry — usable,
  // but no symbolication, no grouping, no "view in source" link.
  final event = SentryEvent(
    level: SentryLevel.fatal,
    tags: {'runtime': 'rust', 'recovered_from_disk': 'true'},
    exceptions: [_buildSentryExceptionFromRustPanic(json)],
  );
  await Sentry.captureEvent(event);
  await file.delete();
}
```

`_buildSentryExceptionFromRustPanic` parses the Rust backtrace text format (`<frame N>: <symbol> at <file>:<line>`) into `SentryStackFrame`. This is the part that takes real effort — Rust backtraces in different build modes (debug vs release vs `RUST_BACKTRACE=full`) format differently, and we want this robust to all three.

**Acceptable degraded mode** if event reconstruction proves too fragile in impl: fall back to `Sentry.captureMessage(level: fatal, message: <full json string>, ...)` with the same tags. Dev can read the panic file content in the Sentry message body — symbolication is lost but every other piece of info survives. Decide during impl based on how clean the Rust backtrace parsing turns out.

#### D5. `anyhow::Error` capture at FFI boundaries

The current `api.rs` exports **19 `pub fn`** total, of which **16 return `anyhow::Result<_>`**. Each of those 16 must be wrapped.

**Critical fix from prior draft** — original used `sentry::configure_scope` which is the *exact* global-scope leak issue this plan calls out as anti-pattern in Item A D7. Concurrent FFI calls (Dart code commonly calls into Rust from multiple isolates / async tasks) would cross-tag each other's events.

**Correct pattern:** use `sentry::with_scope`, which is per-capture and does not mutate the hub's main scope:

```rust
fn instrumented_call<T>(
    op: &'static str,
    f: impl FnOnce() -> anyhow::Result<T>,
) -> anyhow::Result<T> {
    match f() {
        Ok(v) => Ok(v),
        Err(e) => {
            sentry::with_scope(
                |scope| { scope.set_tag("op", op); },
                || sentry::integrations::anyhow::capture_anyhow(&e),
            );
            Err(e)
        }
    }
}
```

**Async composition:** the sync wrapper above doesn't compose with `async fn` ergonomically (lifetime gymnastics passing `&'static str` through awaits, scope-binding interaction with the future's poll lifetime). Two viable approaches:

  1. **Macro `instrumented_async!("op", async { ... })`** that expands to capture-on-Err around the future at the call site. Borrow-checker is happy because the macro expands inline.
  2. **Async helper:** `async fn instrumented_async<F, T>(op: &'static str, f: F) -> anyhow::Result<T> where F: Future<Output = anyhow::Result<T>>`. Single `.await` at call site (`instrumented_async("op", async { ... }).await`), straightforward signature.

Both are one-await at the call site. Decide between #1 and #2 during impl based on:
  - Readability when applied to all 16 `pub fn` bodies.
  - Whether the chosen form plays nicely with FRB's `#[frb]` attribute macros (verify before committing to a pattern).
  - Whether `sentry::with_scope` correctly binds the scope across the future's await points — this is the **load-bearing semantic question**. `with_scope` in current sentry-rust is sync; using it around an async future may not bind the scope for the entire future's lifetime. Smoke-test with concurrent panicking tasks before adopting (see DoD: concurrent panic test).

Apply incrementally, not all-at-once — easier to revert if the chosen pattern interacts badly with FRB codegen.

**FRB regen impact:** wrapping `pub fn` bodies does not change FFI signatures, so FRB-generated bindings should not change. Verify by running `flutter_rust_bridge_codegen generate` after the wrap and confirming `lib/bridge/*` produces zero diff. If it does diff, the wrap leaked an internal type into the signature — back out and refactor.

#### D5b. Panic `op`-tagging limitation

The plan above tags `op` only on the `Err` branch of `instrumented_call`. **A panic does not reach that `Err` branch** — it unwinds past the `match` statement and is caught by the `std::panic::set_hook` registered in D4, which has no knowledge of which `pub fn` was running.

**Consequence:** anyhow errors from `pub fn` X get `op: rust.X` tag. Panics from inside `pub fn` X get the panic message and backtrace, but **no `op` tag** — Sentry sees them as runtime-tagged Rust panics with no operation context.

**Options to address (decide during impl based on cost/benefit):**

  1. **Accept the gap.** Panics in our codebase are bugs (assertions, unwraps); the backtrace alone identifies which `pub fn` was running. This is what the plan currently commits to. `op` becomes a feature of the error path, not the panic path.
  2. **Thread-local "current op" stack.** `instrumented_call` pushes `op` onto a thread-local before the body, pops after. The panic hook reads the thread-local at panic time and writes `op` into the panic file / Sentry event. Works for sync calls, breaks for async (Tokio moves futures across worker threads, the thread-local doesn't follow). Implementing correctly across `tokio::spawn` requires task-local storage, not thread-local.
  3. **Tokio task-local + sync thread-local hybrid.** `tokio::task_local!` for async paths, `thread_local!` for sync paths, panic hook checks both. Implementable, but doubles the wrapper complexity.

The plan **commits to option 1** by default. If during impl smoke testing we find panics are common enough that missing `op` tags is hurting triage, escalate to option 3 in a follow-up. Document this trade-off in `telemetry.rs` so future readers understand why panics don't carry `op`.

#### D6. Breadcrumb crossing: skip

Rust *could* receive Dart breadcrumbs over FFI, or vice versa. **Skip.** Two parallel Sentry SDKs sharing nothing but DSN is fine; Sentry server merges events by `event_id`. Cross-FFI breadcrumb sync is high cost / low value.

#### D7. Build-time gating

Add `sentry` crate behind a Cargo feature flag, syntax along the lines of:

```toml
[dependencies]
sentry = { version = "...", optional = true, default-features = false, features = ["anyhow", "panic", "backtrace"] }

[features]
telemetry = ["dep:sentry"]
```

(Exact version, default-features, and feature names to be verified against the version pinned at impl time. Don't copy-paste this verbatim; it's directional.) CI release builds enable `--features telemetry`; local dev builds may skip to avoid pulling transitive deps for fast `cargo check` cycles.

Default-on in release, off in debug. `--features telemetry` controllable via `scripts/dev.sh`.

### File plan

New: `native/src/telemetry.rs`
- `init_telemetry(dsn: Option<String>, release: String, panic_dir: PathBuf)` — full signature with all three params (see D2 wiring snippet). Plan deliberately calls this *after* `RustLib::init`, so the function itself can be FRB-exported without bootstrap-order paradox.
- `install_panic_hook(panic_dir: PathBuf)` — guarded by `OnceLock` for hot-restart idempotency (see D8).
- `write_panic_file(panic_dir: &Path, info: &PanicInfo) -> std::io::Result<()>` — writes structured JSON.
- `instrumented_call` (sync) and `instrumented_async!` macro **or** `instrumented_async` async helper — choose during impl per D5 trade-offs.
- Cfg-gated on `feature = "telemetry"` — non-telemetry build provides empty stubs that satisfy callers without pulling Sentry deps.

Modify: `native/src/lib.rs`
- Add `mod telemetry;` and `pub use telemetry::init_telemetry;`.

Modify: `native/src/api.rs`
- Wrap each `pub` FFI fn body with `instrumented!("rust.<op>", { ... })`. Audit `api.rs` first to enumerate the actual function set (don't trust any count from this plan — it's not been verified).
- Rebuild FRB bindings.

Modify: `native/Cargo.toml`
- Add optional sentry deps + feature flag.

Modify: `lib/main.dart` (and/or `_initRustBridge` helper inside it)
- After `RustLib.init` succeeds and before `downloadManagerInit`, init Rust telemetry with the same DSN, brand-prefixed release, and Dart-resolved panic dir (see D2 wiring snippet above for full call). This intentionally runs after FRB init — see D2's "chicken-and-egg" discussion. The plan does NOT cover panics during `RustLib.init` itself.
- Helper `_resolveRustPanicDir()` returns the absolute path to a brand-specific subdirectory under the app support directory. Naive implementation `path.join(supportDir, BrandConfig.current.brand.name, 'rust_panics')` is unsafe on Windows: `path_provider_windows` returns `<RoamingAppData>\<CompanyName>\<ProductName>` per the platform plugin, where `<ProductName>` *may already match the brand name* (it's set by `windows/runner/main.cpp` from the app's product info). Joining brand again would produce `.../ssvid/ssvid/rust_panics` for SSvid users.

  **Required logic** (not "smoke-test it"):
  ```dart
  Future<String> _resolveRustPanicDir() async {
    final support = await getApplicationSupportDirectory();
    final brand = BrandConfig.current.brand.name;
    // Only append brand if the support dir's basename doesn't already match it
    // (case-insensitive on Windows). This handles path_provider_windows
    // returning `.../<CompanyName>/<ProductName>` where ProductName == brand.
    final basename = path.basename(support.path).toLowerCase();
    final dir = (basename == brand.toLowerCase())
        ? path.join(support.path, 'rust_panics')
        : path.join(support.path, brand, 'rust_panics');
    await Directory(dir).create(recursive: true);
    return dir;
  }
  ```
  Tests must cover both shapes (basename matches brand → don't double-nest; basename differs → append brand) on a synthetic `Directory` mock. Real-device verification on Windows + macOS + Linux still required at smoke-test stage, but the logic is no longer "hope it works."

  Centralize this in a single helper and have `StartupService.scanRustPanics()` call the same helper — never hardcode the path resolution in two places.

Modify: `lib/core/services/startup_service.dart`
- Add a phase that scans the same brand-resolved `rust_panics/` directory (re-resolve via the same helper, do NOT hardcode any brand name), reads each JSON panic file, reconstructs a `SentryEvent` (see D4), uploads via `Sentry.captureEvent`, deletes the file on success. Runs in deferred-startup phase (after first frame, non-critical path).

Modify: `scripts/dev.sh` and `.github/workflows/release.yml`
- Add `--features telemetry` to release builds; debug builds opt-out unless dev passes a flag.

### Definition of done

- `cargo test` passes with and without `--features telemetry`.
- All 16 `anyhow::Result`-returning `pub fn` in `api.rs` wrapped (enumerate in PR description, don't trust this number — verify with `grep -c '^pub.*anyhow::Result' native/src/api.rs` at impl time).
- FRB regeneration produces zero diff in `lib/bridge/*` (proves no signature leak).
- **Forced anyhow error in `ytdlp_extract_info` produces a Sentry event with: `runtime: rust` tag, `op: rust.ytdlp.extract_info` tag, full backtrace, error message.** This is achievable because `instrumented_call` runs `with_scope` on the `Err` branch.
- **Forced panic** (e.g. `unwrap()` on `None`) in `ytdlp_extract_info` produces a Sentry event with: `runtime: rust` tag, full Rust backtrace, panic message. **`op` tag is NOT guaranteed** for panics — see "Panic op-tagging limitation" below.
- Forced anyhow error chain (3 levels: `with_context` × 2) → Sentry event preserves all 3 levels in the exception chain.
- Concurrent error test (NOT panic): spawn two Tokio tasks, return `anyhow::Err` from both with different `op` values, verify each Sentry event has its own `op` tag (proves the `with_scope` fix works for the error path).
- Concurrent panic test: spawn two Tokio tasks, panic in both. Verify each panic produces a Sentry event with `runtime: rust` and full backtrace. Whether `op` tag is correctly attributed is a *test of the design*, not an assertion — record actual behavior, drive next steps from there.
- Smoke test: `kill -9` the app immediately after triggering a Rust panic, restart, verify next launch uploads the panic file from disk and the resulting Sentry event has a parsed Rust stack (or, in degraded mode, the full panic JSON in the message body).
- Hot-restart idempotency: trigger hot restart 3 times, verify panic hook is installed exactly once (no duplicate panic files / events on next panic).
- Brand test: build VidCombo brand, verify panic files land in `<app_data>/vidcombo/rust_panics/`, NOT `<app_data>/ssvid/`.
- Sentry release tag matches `${brand}@${app_version}` from Dart side (NOT `0.1.0` from Cargo).
- Build size delta measured and documented in the PR description (no specific number committed in plan).
- Verify `Cargo.toml` feature names against the current `sentry` crate docs at impl time. The names `sentry-anyhow` and `sentry-panic` are *crate* names; whether they're enabled as features of `sentry = { features = [...] }` or as separate dep entries depends on the version pinned. Plan does not commit to syntax.

### Decided design choices (no longer open)

These were initially open but the plan has resolved them. Recorded for future readers.

- **Single Sentry project for both Dart and Rust events** with `runtime` tag distinguishing source. Picked over split projects for correlation; crash-free session metrics work cleanly.
- **`_guard` stored in `OnceLock`, never explicitly dropped.** Sentry's background thread auto-flushes every few seconds, and desktop apps rarely shut down gracefully enough to need synchronous flush. Documented as a known limitation, not blocking.

### Open questions (require impl-time validation)

- Q1: Tokio panic in worker thread — does `sentry-panic` see it? Need to verify. Tokio's default behavior depends on runtime config; `tokio::spawn`'d tasks may swallow panics into the `JoinHandle`. May need `tokio::task::Builder::spawn` with custom panic handler, or a wrapper around `spawn`. **Test during impl with the concurrent-panic smoke test in DoD.** This is the only open question that can change the design.

---

## Sequencing

Suggested order (each can be a separate PR):

1. **Item A foundation** (`instrumentation.dart` + `safeCaptureException` + 5-10 sample migrations) — 1 day. Lands first because Items B and C will *use* `instrumentedAsync` internally.
2. **Item B HTTP interceptor** — 0.5 day. Quick win, immediate value.
3. **Item C Rust telemetry** — 2-3 days. Most complex, do last so we can use Items A/B patterns where they apply.
4. **Item A migration** — incremental, 2-4 weeks elapsed time, one PR per domain.

Total foundation: **3.5-4.5 dev days**, plus migration tail.

Do *not* parallelize A and B — B depends on the `instrumentedAsync` signature being final. Doing them concurrently risks two PRs converging on slightly-different conventions.

## Out of scope (deliberately)

These came up during planning. All real, none belong in this plan:

- **`WM_POWERBROADCAST` Windows native handler** — separate plan (Item #3 from the audit).
- **Sentry transactions / performance monitoring** — separate plan (Item #8).
- **Settings change breadcrumbs** — trivial, do without a plan (Item #9).
- **GPU/OS context tags** — trivial, do without a plan (audit Item #6).
- **App lifecycle breadcrumbs** — trivial (5 lines in `app_scaffold.dart`), do without a plan.
- **Crash recovery detection** — separate plan (audit Item #10), modest complexity.

The triviality split is intentional: this document only covers the three items where API choices propagate. Trivial items don't need plans because there's nothing to align on.
