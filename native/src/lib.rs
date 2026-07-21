mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
/// SSvid Native Core
/// Rust modules for high-performance download and file system operations

mod api;
mod download;
mod filesystem;
mod ytdlp;
mod context;
pub(crate) mod telemetry;

// Re-export API functions for flutter_rust_bridge.
// `flutter_rust_bridge.yaml: rust_input: "crate::api"` — FRB only inspects
// `crate::api`, so any function that needs a Dart binding (including
// `init_telemetry`) is declared as a `pub fn` in `api.rs`. The telemetry
// module is a private implementation detail wrapped by `api::init_telemetry`.
pub use api::*;

// FRB will generate the bridge code automatically
