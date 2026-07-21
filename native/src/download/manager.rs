/// Download Manager - Manages concurrent downloads with pause/resume/cancel support
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{Mutex, Semaphore, mpsc};
use anyhow::Result;
use uuid::Uuid;
use super::config::DownloadConfig;
use super::engine::{DownloadEngine, DownloadProgress as EngineProgress};
use super::hls_engine::HlsEngine;
use super::segmented_engine::SegmentedEngine;

/// After reaching a terminal state (Completed / Failed / Cancelled), a task
/// is kept around for this long so the Dart caller has a window in which
/// `get_progress` still returns the final status. Any operation that takes
/// the tasks lock calls [`sweep_expired_tasks`] to drop entries older than
/// this — the bound stops the HashMap growing without limit when the Dart
/// side crashes (or simply forgets to call) `cleanup_download`.
const TERMINAL_TTL: Duration = Duration::from_secs(600);

/// Wrapper enum for single-stream, segmented, and HLS download engines
pub enum EngineType {
    Single(DownloadEngine),
    Segmented(SegmentedEngine),
    Hls(HlsEngine),
}

impl EngineType {
    pub fn pause(&self) {
        match self {
            EngineType::Single(e) => e.pause(),
            EngineType::Segmented(e) => e.pause(),
            EngineType::Hls(e) => e.pause(),
        }
    }

    pub fn resume(&self) {
        match self {
            EngineType::Single(e) => e.resume(),
            EngineType::Segmented(e) => e.resume(),
            EngineType::Hls(e) => e.resume(),
        }
    }

    pub fn cancel(&self) {
        match self {
            EngineType::Single(e) => e.cancel(),
            EngineType::Segmented(e) => e.cancel(),
            EngineType::Hls(e) => e.cancel(),
        }
    }

    pub fn get_downloaded_bytes(&self) -> u64 {
        match self {
            EngineType::Single(e) => e.get_downloaded_bytes(),
            EngineType::Segmented(e) => e.get_downloaded_bytes(),
            EngineType::Hls(e) => e.get_downloaded_bytes(),
        }
    }

    pub fn get_total_bytes(&self) -> u64 {
        match self {
            EngineType::Single(e) => e.get_total_bytes(),
            EngineType::Segmented(e) => e.get_total_bytes(),
            EngineType::Hls(e) => e.get_total_bytes(),
        }
    }
}

/// Download status
#[derive(Debug, Clone, PartialEq)]
pub enum DownloadStatus {
    Pending,
    Downloading,
    Paused,
    Completed,
    Failed(String),
    Cancelled,
}

/// Download task
pub struct DownloadTask {
    pub id: Uuid,
    pub url: String,
    pub output_path: PathBuf,
    pub total_bytes: u64,
    pub downloaded_bytes: u64,
    pub resume_offset: u64,  // Byte offset to resume from
    pub max_speed_bytes: u64, // 0 = unlimited
    pub num_segments: u32,    // 1 = single-stream, 2+ = segmented
    pub status: DownloadStatus,
    pub engine: Arc<Mutex<EngineType>>,
    pub progress_rx: Option<mpsc::UnboundedReceiver<EngineProgress>>,
    /// Instant at which the task reached a terminal state (Completed,
    /// Failed, or Cancelled). Used by [`sweep_expired_tasks`] to bound
    /// memory for tasks whose Dart-side `cleanup_download` never fires.
    /// `None` while the task is still active (Pending / Downloading / Paused).
    pub terminal_at: Option<Instant>,
}

/// Download manager - singleton managing all active downloads
pub struct DownloadManager {
    tasks: Arc<Mutex<HashMap<Uuid, DownloadTask>>>,
    max_concurrent: usize,
    semaphore: Arc<Semaphore>,
}

impl DownloadManager {
    /// Returns true if the URL points to an HLS/M3U8 playlist.
    fn is_hls_url(url: &str) -> bool {
        let lower = url.to_lowercase();
        // Strip query string and fragment for extension check
        let path_part = lower.split('?').next().unwrap_or(&lower);
        let path_part = path_part.split('#').next().unwrap_or(path_part);
        path_part.ends_with(".m3u8")
    }

    /// Create new download manager
    pub fn new(max_concurrent: usize) -> Self {
        let max = max_concurrent.max(1);
        Self {
            tasks: Arc::new(Mutex::new(HashMap::new())),
            max_concurrent: max,
            semaphore: Arc::new(Semaphore::new(max)),
        }
    }

    /// Start a new download with optional resume offset, speed limit, segment count, user agent, and proxy.
    /// Legacy API — delegates to `start_download_with_config` using a default `DownloadConfig`.
    pub async fn start_download(
        &self,
        id: Uuid,
        url: String,
        output_path: String,
        resume_offset: u64,
        max_speed_bytes: u64,
        num_segments: u32,
        user_agent: Option<String>,
        proxy_url: Option<String>,
    ) -> Result<()> {
        let config = DownloadConfig {
            user_agent,
            proxy_url,
            ..Default::default()
        };
        self.start_download_with_config(
            id, url, output_path, resume_offset, max_speed_bytes, num_segments, config,
        ).await
    }

    /// Start a new download with full `DownloadConfig` (IDM mode — custom headers/cookies).
    pub async fn start_download_with_config(
        &self,
        id: Uuid,
        url: String,
        output_path: String,
        resume_offset: u64,
        max_speed_bytes: u64,
        num_segments: u32,
        config: DownloadConfig,
    ) -> Result<()> {
        let mut tasks = self.tasks.lock().await;

        // Check if already exists
        if tasks.contains_key(&id) {
            anyhow::bail!("Download with id {} already exists", id);
        }

        // Create progress channel
        let (progress_tx, progress_rx) = mpsc::unbounded_channel();

        let segments = num_segments.clamp(1, 16);

        // Create engine: HLS for m3u8 URLs, segmented for multi-segment, single for 1 segment
        let engine_type = if Self::is_hls_url(&url) {
            // HLS/M3U8 engine — handles playlist parsing + segment concatenation
            let mut hls_engine = HlsEngine::with_config(config);
            hls_engine.set_progress_channel(progress_tx);
            EngineType::Hls(hls_engine)
        } else if segments > 1 && resume_offset == 0 {
            // Segmented engine (resume_offset not applicable — segmented engine handles its own resume via .part files)
            let mut seg_engine = SegmentedEngine::with_config(segments, config);
            seg_engine.set_progress_channel(progress_tx);
            if max_speed_bytes > 0 {
                seg_engine.set_max_speed(max_speed_bytes);
            }
            EngineType::Segmented(seg_engine)
        } else {
            // Single-stream engine (or resuming existing single-stream download)
            let mut engine = DownloadEngine::with_config(config);
            engine.set_progress_channel(progress_tx);
            if max_speed_bytes > 0 {
                engine.set_max_speed(max_speed_bytes);
            }
            EngineType::Single(engine)
        };

        // Create task
        let task = DownloadTask {
            id,
            url: url.clone(),
            output_path: PathBuf::from(output_path.clone()),
            total_bytes: 0,
            downloaded_bytes: resume_offset,
            resume_offset,
            max_speed_bytes,
            num_segments: segments,
            status: DownloadStatus::Pending,
            engine: Arc::new(Mutex::new(engine_type)),
            progress_rx: Some(progress_rx),
            terminal_at: None,
        };

        tasks.insert(id, task);
        drop(tasks); // Release lock before spawning

        // Spawn download task with semaphore permit for concurrency control
        let tasks_ref = Arc::clone(&self.tasks);
        let semaphore = Arc::clone(&self.semaphore);
        tokio::spawn(async move {
            // Acquire semaphore permit — blocks if max_concurrent downloads are active
            let _permit = semaphore.acquire().await.expect("semaphore closed");

            if let Err(e) = Self::run_download(tasks_ref.clone(), id, url, output_path, resume_offset).await {
                // Mark as failed — unless the caller already set Cancelled
                // on this task (narrow race where engine returned Err right
                // as cancel() flipped the flag; Cancelled is the more
                // user-honest outcome, so we preserve it).
                let mut tasks_lock = tasks_ref.lock().await;
                if let Some(task) = tasks_lock.get_mut(&id) {
                    if !matches!(task.status, DownloadStatus::Cancelled) {
                        task.status = DownloadStatus::Failed(e.to_string());
                    }
                    task.terminal_at = Some(Instant::now());
                }
            }
            // _permit dropped here → releases slot for next download
        });

        Ok(())
    }

    /// Internal download runner — dispatches to single-stream or segmented engine
    async fn run_download(
        tasks: Arc<Mutex<HashMap<Uuid, DownloadTask>>>,
        id: Uuid,
        url: String,
        output_path: String,
        resume_offset: u64,
    ) -> Result<()> {
        // Update status to downloading
        {
            let mut tasks_lock = tasks.lock().await;
            if let Some(task) = tasks_lock.get_mut(&id) {
                task.status = DownloadStatus::Downloading;
            }
        }

        // Get engine
        let engine = {
            let tasks_lock = tasks.lock().await;
            tasks_lock
                .get(&id)
                .map(|task| Arc::clone(&task.engine))
                .ok_or_else(|| anyhow::anyhow!("Task not found"))?
        };

        // Run download — dispatch based on engine type
        {
            let mut engine_guard = engine.lock().await;
            match &mut *engine_guard {
                EngineType::Single(e) => {
                    e.download_with_offset(&url, &output_path, resume_offset).await?;
                }
                EngineType::Segmented(e) => {
                    e.download_segmented(&url, &output_path).await?;
                }
                EngineType::Hls(e) => {
                    e.download_hls(&url, &output_path).await?;
                }
            }
        }

        // Update status to completed — BUT only if the task was not
        // cancelled between the last await and now. User-visible cancel
        // beats a lucky in-flight completion; otherwise the UI shows
        // "completed" for a request the user explicitly aborted.
        {
            let mut tasks_lock = tasks.lock().await;
            if let Some(task) = tasks_lock.get_mut(&id) {
                if !matches!(task.status, DownloadStatus::Cancelled) {
                    task.status = DownloadStatus::Completed;
                    let engine_guard = task.engine.lock().await;
                    task.downloaded_bytes = engine_guard.get_downloaded_bytes();
                }
                task.terminal_at = Some(Instant::now());
            }
        }

        Ok(())
    }

    /// Drop tasks that have been in a terminal state longer than
    /// [`TERMINAL_TTL`]. Caller holds the tasks lock. Exists so the
    /// HashMap stays bounded even when `cleanup_download` is never
    /// invoked from the Dart side (crash, stream subscription dropped
    /// early, caller error).
    fn sweep_expired_tasks(tasks: &mut HashMap<Uuid, DownloadTask>) {
        let now = Instant::now();
        tasks.retain(|_, task| match task.terminal_at {
            Some(t) => now.duration_since(t) < TERMINAL_TTL,
            None => true,
        });
    }

    /// Pause a download and save resume offset
    pub async fn pause_download(&self, id: Uuid) -> Result<()> {
        let mut tasks = self.tasks.lock().await;

        let task = tasks
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("Download not found"))?;

        if task.status != DownloadStatus::Downloading {
            anyhow::bail!("Download is not in downloading state");
        }

        let engine_guard = task.engine.lock().await;
        engine_guard.pause();

        task.resume_offset = engine_guard.get_downloaded_bytes();
        task.downloaded_bytes = task.resume_offset;
        task.status = DownloadStatus::Paused;

        Ok(())
    }

    /// Resume a download
    pub async fn resume_download(&self, id: Uuid) -> Result<()> {
        let mut tasks = self.tasks.lock().await;

        let task = tasks
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("Download not found"))?;

        if task.status != DownloadStatus::Paused {
            anyhow::bail!("Download is not in paused state");
        }

        let engine_guard = task.engine.lock().await;
        engine_guard.resume();
        task.status = DownloadStatus::Downloading;

        Ok(())
    }

    /// Cancel a download
    pub async fn cancel_download(&self, id: Uuid) -> Result<()> {
        let mut tasks = self.tasks.lock().await;

        let task = tasks
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("Download not found"))?;

        let engine_guard = task.engine.lock().await;
        engine_guard.cancel();
        task.status = DownloadStatus::Cancelled;
        task.terminal_at = Some(Instant::now());

        Ok(())
    }

    /// Get download progress
    pub async fn get_progress(&self, id: Uuid) -> Result<DownloadProgress> {
        let mut tasks = self.tasks.lock().await;
        Self::sweep_expired_tasks(&mut tasks);

        let task = tasks
            .get(&id)
            .ok_or_else(|| anyhow::anyhow!("Download not found"))?;

        let engine_guard = task.engine.lock().await;
        let downloaded = engine_guard.get_downloaded_bytes();
        let total = engine_guard.get_total_bytes();

        Ok(DownloadProgress {
            id,
            downloaded_bytes: downloaded,
            total_bytes: total,
            status: format!("{:?}", task.status),
        })
    }

    /// Get all active downloads
    pub async fn get_all_downloads(&self) -> Vec<DownloadProgress> {
        let mut tasks = self.tasks.lock().await;
        Self::sweep_expired_tasks(&mut tasks);

        let mut results = Vec::new();
        for (id, task) in tasks.iter() {
            if let Ok(engine_guard) = task.engine.try_lock() {
                results.push(DownloadProgress {
                    id: *id,
                    downloaded_bytes: engine_guard.get_downloaded_bytes(),
                    total_bytes: engine_guard.get_total_bytes(),
                    status: format!("{:?}", task.status),
                });
            }
        }
        results
    }

    /// Remove completed/failed/cancelled downloads
    pub async fn cleanup_download(&self, id: Uuid) -> Result<()> {
        let mut tasks = self.tasks.lock().await;
        Self::sweep_expired_tasks(&mut tasks);

        if let Some(task) = tasks.get(&id) {
            match task.status {
                DownloadStatus::Completed
                | DownloadStatus::Failed(_)
                | DownloadStatus::Cancelled => {
                    tasks.remove(&id);
                    Ok(())
                }
                _ => anyhow::bail!("Cannot cleanup active download"),
            }
        } else {
            anyhow::bail!("Download not found")
        }
    }

    /// Get progress stream receiver for a download
    /// This consumes the receiver, so can only be called once per download
    pub async fn take_progress_stream(&self, id: Uuid) -> Result<mpsc::UnboundedReceiver<EngineProgress>> {
        let mut tasks = self.tasks.lock().await;

        let task = tasks
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("Download not found"))?;

        task.progress_rx
            .take()
            .ok_or_else(|| anyhow::anyhow!("Progress stream already consumed"))
    }
}

/// Download progress info
#[derive(Debug, Clone)]
pub struct DownloadProgress {
    pub id: Uuid,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub status: String,
}
