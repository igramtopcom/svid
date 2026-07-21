/// Global application context - shared state across FFI calls
use std::sync::Arc;
use tokio::sync::{Mutex, OnceCell};
use reqwest::Client;
use anyhow::Result;
use crate::download::manager::DownloadManager;

/// Application context with shared resources
pub struct AppContext {
    pub http_client: Client,
    pub download_manager: Arc<Mutex<DownloadManager>>,
}

impl AppContext {
    /// Create new application context
    pub fn new(max_concurrent_downloads: usize) -> Self {
        let http_client = Client::builder()
            .pool_max_idle_per_host(10)
            .timeout(std::time::Duration::from_secs(300))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            http_client,
            download_manager: Arc::new(Mutex::new(DownloadManager::new(
                max_concurrent_downloads,
            ))),
        }
    }
}

/// Global context singleton
static APP_CONTEXT: OnceCell<Arc<AppContext>> = OnceCell::const_new();

/// Initialize global context (call once at app start)
pub async fn init_context(max_concurrent_downloads: usize) -> Result<()> {
    APP_CONTEXT
        .set(Arc::new(AppContext::new(max_concurrent_downloads)))
        .map_err(|_| anyhow::anyhow!("Context already initialized"))?;
    Ok(())
}

/// Get global context reference
pub fn get_context() -> Result<&'static Arc<AppContext>> {
    APP_CONTEXT
        .get()
        .ok_or_else(|| anyhow::anyhow!("Context not initialized. Call init_context() first."))
}
