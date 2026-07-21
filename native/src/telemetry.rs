//! Sentry-rust telemetry integration for Item C of the instrumentation plan.
//!
//! Two surfaces:
//! - [`init_telemetry`] — exposed via FRB; called from Dart `main()` after
//!   `RustLib::init` succeeds (chicken-and-egg, see plan D2).
//! - [`instrumented_call`] / [`instrumented_async`] — wrap each
//!   `pub fn` in `api.rs` that returns `anyhow::Result`, capturing errors
//!   with a per-capture scope so concurrent FFI calls don't cross-tag
//!   each other.
//!
//! All Sentry interaction is `cfg`-gated on `feature = "telemetry"` so a
//! local `cargo check` build (no telemetry) compiles fast and produces
//! identical FFI bindings.
//!
//! Critical design points (from plan):
//! - **Per-capture scope**: use `sentry::with_scope`, NEVER
//!   `sentry::configure_scope` (global mutation, leaks across concurrent
//!   futures — same anti-pattern as Dart D7).
//! - **Panic op-tagging is NOT promised**: the panic hook fires in a sync
//!   context with no per-call op visibility. Plan D5b commits to option
//!   1 (accept the gap) — anyhow errors get `op` tags, panics get
//!   `runtime: rust` + backtrace but no op.
//! - **Idempotent panic hook**: protected by `OnceLock` so hot-restart
//!   doesn't stack hooks.
//! - **File fallback for panics**: write structured JSON to disk so the
//!   next launch can upload events that died before Sentry could flush.

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use std::sync::Mutex;

#[cfg(feature = "telemetry")]
static TELEMETRY_GUARD: Mutex<Option<sentry::ClientInitGuard>> = Mutex::new(None);

/// Set exactly once when the panic hook has been installed. Hot-restart
/// re-enters init_telemetry, but we MUST NOT chain another panic hook on
/// top of the previous one — that would duplicate panic files and Sentry
/// events.
static PANIC_HOOK_INSTALLED: OnceLock<()> = OnceLock::new();

/// Caches the Dart-provided release string (e.g. `"svid@1.3.7+12"`) so
/// `write_panic_file` can stamp panic records with the SAME release tag
/// the live Sentry client uses. Without this, recovered-from-disk panics
/// would tag with `CARGO_PKG_VERSION` (= `"0.1.0"`) and aggregate as a
/// separate "version" in the Sentry dashboard, hiding the bug.
///
/// Updated atomically on every `init_telemetry` call so hot restart with
/// a different brand string (rare but possible) reflects the new value.
static APP_RELEASE: Mutex<Option<String>> = Mutex::new(None);

/// Initialize Sentry-rust telemetry.
///
/// Called from Dart `main()` after `RustLib::init`. Idempotent: hot
/// restart re-invokes this safely.
///
/// # Args
/// - `dsn`: Sentry DSN. `None` (or empty) → telemetry disabled, only the
///   on-disk panic fallback runs.
/// - `release`: e.g. `"svid@1.3.7+12"`. Used as the Sentry `release` tag
///   so events from different shipped versions don't aggregate together.
///   Comes from Dart so it tracks `AppConstants.appVersion` and brand,
///   NOT `env!("CARGO_PKG_VERSION")` (which is the unrelated Rust crate
///   version `0.1.0`).
/// - `panic_dir`: brand-resolved absolute path to the directory where
///   panic JSON files get written when the in-process Sentry transport
///   can't deliver. The Dart side scans this on next launch and uploads.
pub fn init_telemetry(dsn: Option<String>, release: String, panic_dir: String) {
    let panic_dir = PathBuf::from(panic_dir);

    // Cache the Dart-provided release so write_panic_file can stamp the
    // SAME tag as the live Sentry client. Without this, recovered panic
    // files would tag with the unrelated Rust crate version 0.1.0.
    if let Ok(mut slot) = APP_RELEASE.lock() {
        *slot = Some(release.clone());
    }

    #[cfg(feature = "telemetry")]
    if let Some(dsn) = dsn.clone().filter(|s| !s.is_empty()) {
        let guard = sentry::init((
            dsn,
            sentry::ClientOptions {
                release: Some(release.clone().into()),
                attach_stacktrace: true,
                ..Default::default()
            },
        ));
        // Replace any previous guard (hot-restart). The old guard's Drop
        // would normally flush — that's fine, telemetry doesn't depend on
        // explicit flush since the background thread auto-flushes.
        if let Ok(mut slot) = TELEMETRY_GUARD.lock() {
            *slot = Some(guard);
        }
    }

    // Always install the panic hook, even without a DSN — the on-disk
    // file fallback is useful by itself.
    if PANIC_HOOK_INSTALLED.set(()).is_ok() {
        install_panic_hook(panic_dir);
    }

    // Suppress unused-variable warnings when telemetry feature is off.
    let _ = (dsn, release);
}

/// Install the global panic hook. Idempotent — caller protects with
/// [`PANIC_HOOK_INSTALLED`].
fn install_panic_hook(panic_dir: PathBuf) {
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        // Always write the panic file to disk first so even a Sentry
        // transport failure leaves a trace.
        let _ = write_panic_file(&panic_dir, info);

        // Forward to the previous hook so std panic printing still
        // happens. Sentry's panic integration also chains through the
        // hook chain when `feature = "panic"` is enabled.
        prev(info);
    }));
}

/// Write a structured JSON panic record to `<panic_dir>/<timestamp>_<thread>.json`.
///
/// Format chosen so the Dart side can reconstruct a `SentryEvent` without
/// having to re-parse human-readable Rust panic output. If parsing the
/// backtrace turns out to be fragile in real builds, the Dart side falls
/// back to `Sentry.captureMessage` with the full JSON in the message body
/// (degraded mode — see plan D4).
fn write_panic_file(panic_dir: &Path, info: &std::panic::PanicHookInfo<'_>) -> std::io::Result<()> {
    use std::fs;
    use std::io::Write;

    fs::create_dir_all(panic_dir)?;

    // Read the Dart-provided release if available (set by init_telemetry).
    // Falls back to the Rust crate version only when Dart never called init
    // — should never happen in production but worth being defensive.
    let release = APP_RELEASE
        .lock()
        .ok()
        .and_then(|guard| guard.clone())
        .unwrap_or_else(|| format!("rust@{}", env!("CARGO_PKG_VERSION")));

    let payload = serde_json::json!({
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "thread": std::thread::current().name().unwrap_or("<unnamed>"),
        "message": format_panic_message(info),
        "location": info.location().map(|l| serde_json::json!({
            "file": l.file(),
            "line": l.line(),
            "column": l.column(),
        })).unwrap_or(serde_json::Value::Null),
        "backtrace": std::backtrace::Backtrace::force_capture().to_string(),
        "release": release,
    });

    let timestamp = chrono::Utc::now().format("%Y%m%dT%H%M%S%3f").to_string();
    let thread = std::thread::current()
        .name()
        .map(|n| n.replace(['/', '\\', ':'], "_"))
        .unwrap_or_else(|| "unnamed".to_string());
    // UUID v4 disambiguates concurrent panics that share thread name and
    // millisecond timestamp (Tokio worker pools easily produce these).
    // Without it, write_panic_file races would silently overwrite/truncate
    // earlier panic records.
    let unique = uuid::Uuid::new_v4();
    let filename = format!("{}_{}_{}.json", timestamp, thread, unique);
    let path = panic_dir.join(filename);

    let mut f = fs::File::create(&path)?;
    f.write_all(payload.to_string().as_bytes())?;
    f.sync_all()?;
    Ok(())
}

fn format_panic_message(info: &std::panic::PanicHookInfo<'_>) -> String {
    if let Some(s) = info.payload().downcast_ref::<&'static str>() {
        return (*s).to_string();
    }
    if let Some(s) = info.payload().downcast_ref::<String>() {
        return s.clone();
    }
    "panic with non-string payload".to_string()
}

/// Sync wrapper for `pub fn`s returning `anyhow::Result<T>`. Captures the
/// error into Sentry with a per-capture scope tagging `op = <name>`.
///
/// Per-capture scope (NOT global) — see plan D7. Concurrent calls don't
/// cross-tag each other.
pub fn instrumented_call<T, F>(op: &'static str, f: F) -> anyhow::Result<T>
where
    F: FnOnce() -> anyhow::Result<T>,
{
    match f() {
        Ok(v) => Ok(v),
        Err(e) => {
            #[cfg(feature = "telemetry")]
            {
                sentry::with_scope(
                    |scope| {
                        scope.set_tag("op", op);
                        scope.set_tag("runtime", "rust");
                    },
                    || {
                        sentry::integrations::anyhow::capture_anyhow(&e);
                    },
                );
            }
            #[cfg(not(feature = "telemetry"))]
            {
                let _ = op; // suppress unused
            }
            Err(e)
        }
    }
}

/// Async wrapper. Same contract as [`instrumented_call`], composed for
/// `async fn` bodies.
///
/// We use a plain async fn (not a macro) because:
/// - One `.await` at the call site (`instrumented_async("op", async { ... }).await`).
/// - Avoids macro hygiene issues with FRB attribute macros.
/// - The borrow-checker is happy because `op: &'static str` doesn't cross
///   await points in a problematic way (it's `Copy`).
///
/// **Async scope-binding caveat (plan D5):** `sentry::with_scope` is sync.
/// Wrapping an awaited future inside its closure does NOT bind the scope
/// for the future's entire poll lifetime — only for the synchronous
/// execution around `with_scope` itself. We therefore await the future
/// FIRST, then call `with_scope` on the (now-resolved) `Err`. This means
/// `op` is correctly attached to the captured event but breadcrumbs added
/// from inside the future via `sentry::add_breadcrumb` (if any) are NOT
/// scoped — they go to the active hub. That's acceptable because we don't
/// add breadcrumbs from the Rust side; all telemetry comes through this
/// wrapper's error path.
pub async fn instrumented_async<T, F>(op: &'static str, f: F) -> anyhow::Result<T>
where
    F: std::future::Future<Output = anyhow::Result<T>>,
{
    match f.await {
        Ok(v) => Ok(v),
        Err(e) => {
            #[cfg(feature = "telemetry")]
            {
                sentry::with_scope(
                    |scope| {
                        scope.set_tag("op", op);
                        scope.set_tag("runtime", "rust");
                    },
                    || {
                        sentry::integrations::anyhow::capture_anyhow(&e);
                    },
                );
            }
            #[cfg(not(feature = "telemetry"))]
            {
                let _ = op;
            }
            Err(e)
        }
    }
}
