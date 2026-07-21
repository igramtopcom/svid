/// Multi-threaded download engine using tokio + reqwest
use anyhow::Result;
use reqwest::{Client, header};
use std::collections::VecDeque;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::fs::File;
use tokio::io::AsyncWriteExt;
use futures_util::StreamExt;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

use super::config::DownloadConfig;

/// Speed sample for sliding window measurement
#[derive(Debug, Clone)]
struct SpeedSample {
    timestamp: Instant,
    bytes: u64,
}

/// Download progress information
#[derive(Debug, Clone)]
pub struct DownloadProgress {
    pub total_bytes: u64,
    pub downloaded_bytes: u64,
    pub speed: f64, // bytes per second
}

pub struct DownloadEngine {
    client: Client,
    is_paused: Arc<AtomicBool>,
    is_cancelled: Arc<AtomicBool>,
    downloaded_bytes: Arc<AtomicU64>,
    total_bytes: Arc<AtomicU64>,
    max_speed_bytes: u64, // 0 = unlimited
    progress_tx: Option<mpsc::UnboundedSender<DownloadProgress>>,
    /// Monotonic counter — used to rotate UA and Accept-Language per HTTP request.
    request_count: Arc<AtomicU64>,
    /// When true, skip per-request header rotation — custom headers from
    /// DownloadConfig (IDM mode) take precedence via default_headers on Client.
    has_custom_headers: bool,
}

impl DownloadEngine {
    /// Default User-Agent used when none is provided.
    const DEFAULT_USER_AGENT: &'static str =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

    /// Pool of browser User-Agent strings rotated per HTTP request.
    const UA_POOL: &'static [&'static str] = &[
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) Gecko/20100101 Firefox/124.0",
        "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
    ];

    /// Accept-Language header values rotated per HTTP request.
    const ACCEPT_LANGUAGE_POOL: &'static [&'static str] = &[
        "en-US,en;q=0.9",
        "en-GB,en;q=0.9",
        "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
        "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7",
        "ko-KR,ko;q=0.9,en-US;q=0.8",
        "zh-CN,zh;q=0.9,en-US;q=0.8",
        "fr-FR,fr;q=0.9,en-US;q=0.8",
        "de-DE,de;q=0.9,en-US;q=0.8",
    ];

    /// Maximum number of retries for HTTP 429 rate-limit responses.
    const MAX_429_RETRIES: u32 = 3;

    /// Backoff durations (seconds) for 429 retries: 5s, 30s, 60s.
    const RETRY_429_BACKOFF_SECS: [u64; 3] = [5, 30, 60];

    pub fn new() -> Self {
        Self::with_user_agent(None)
    }

    pub fn with_user_agent(user_agent: Option<String>) -> Self {
        Self::with_options(user_agent, None)
    }

    /// Create engine with user-agent and optional HTTP proxy.
    /// `proxy_url` accepts standard proxy URLs: `http://host:port`, `socks5://host:port`, etc.
    pub fn with_options(user_agent: Option<String>, proxy_url: Option<String>) -> Self {
        Self::with_config(DownloadConfig {
            user_agent,
            proxy_url,
            ..Default::default()
        })
    }

    /// Create engine from a full `DownloadConfig` (IDM mode — custom headers/cookies).
    pub fn with_config(config: DownloadConfig) -> Self {
        let has_custom = config.has_cookies() || config.has_custom_referer();
        let client = config.build_client();

        Self {
            client,
            is_paused: Arc::new(AtomicBool::new(false)),
            is_cancelled: Arc::new(AtomicBool::new(false)),
            downloaded_bytes: Arc::new(AtomicU64::new(0)),
            total_bytes: Arc::new(AtomicU64::new(0)),
            max_speed_bytes: 0,
            progress_tx: None,
            request_count: Arc::new(AtomicU64::new(0)),
            has_custom_headers: has_custom,
        }
    }

    /// Set progress channel for streaming updates
    pub fn set_progress_channel(&mut self, tx: mpsc::UnboundedSender<DownloadProgress>) {
        self.progress_tx = Some(tx);
    }

    /// Set maximum download speed in bytes/second (0 = unlimited)
    pub fn set_max_speed(&mut self, max_speed_bytes: u64) {
        self.max_speed_bytes = max_speed_bytes;
    }

    /// Pause the download
    pub fn pause(&self) {
        self.is_paused.store(true, Ordering::SeqCst);
    }

    /// Resume the download
    pub fn resume(&self) {
        self.is_paused.store(false, Ordering::SeqCst);
    }

    /// Cancel the download
    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    /// Check if download is paused
    pub fn is_paused(&self) -> bool {
        self.is_paused.load(Ordering::SeqCst)
    }

    /// Check if download is cancelled
    pub fn is_cancelled(&self) -> bool {
        self.is_cancelled.load(Ordering::SeqCst)
    }

    /// Get downloaded bytes so far
    pub fn get_downloaded_bytes(&self) -> u64 {
        self.downloaded_bytes.load(Ordering::SeqCst)
    }

    /// Get total bytes (from Content-Length/Content-Range header)
    pub fn get_total_bytes(&self) -> u64 {
        self.total_bytes.load(Ordering::SeqCst)
    }

    /// Download file from URL to path with streaming and progress tracking
    /// Supports resume from offset via HTTP Range requests
    pub async fn download(&mut self, url: &str, path: &str) -> Result<()> {
        self.download_with_offset(url, path, 0).await
    }

    /// Download with resume from specific byte offset
    pub async fn download_with_offset(&mut self, url: &str, path: &str, resume_offset: u64) -> Result<()> {
        const MAX_STREAM_RETRIES: u32 = 3;

        // Reset state
        self.is_paused.store(false, Ordering::SeqCst);
        self.is_cancelled.store(false, Ordering::SeqCst);

        // If resuming, start from offset
        self.downloaded_bytes.store(resume_offset, Ordering::SeqCst);

        let path_buf = Path::new(path);

        // Create parent directories if needed
        if let Some(parent) = path_buf.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let start_time = Instant::now();
        let mut stream_retry_count: u32 = 0;
        // 429 rate-limit retries are separate from stream-error retries.
        // Backoff: 5s, 30s, 60s — rate limits need longer waits than stream errors.
        let mut retry_429_count: u32 = 0;

        // Outer retry loop: reconnects on mid-stream errors or 429 rate limits
        loop {
            let current_offset = self.downloaded_bytes.load(Ordering::SeqCst);

            // Build request — IDM mode uses Client's default_headers (custom Cookie,
            // Referer, UA from browser session). Standard mode rotates headers per request.
            let mut request = self.client.get(url);

            if !self.has_custom_headers {
                // Standard mode: rotate UA, Accept-Language, Referer per request
                let req_num = self.request_count.fetch_add(1, Ordering::Relaxed) as usize;
                let ua = Self::UA_POOL[req_num % Self::UA_POOL.len()];
                let lang = Self::ACCEPT_LANGUAGE_POOL[req_num % Self::ACCEPT_LANGUAGE_POOL.len()];
                request = request
                    .header(header::USER_AGENT, ua)
                    .header(header::ACCEPT_LANGUAGE, lang);
                if let Some(ref r) = Self::extract_referer(url) {
                    request = request.header(header::REFERER, r.as_str());
                }
            }
            // else: IDM mode — Client's default_headers already have the correct
            // Cookie, Referer, Origin, UA from the browser session. Don't override.
            if current_offset > 0 {
                request = request.header(header::RANGE, format!("bytes={}-", current_offset));
            }

            let response = request
                .send()
                .await
                .map_err(|e| anyhow::anyhow!("Request failed: {}", e))?;

            // Check status
            let status = response.status();

            // Non-retryable HTTP errors: fail immediately with structured prefixes
            // Prefixes are parsed by DownloadErrorClassifier on the Flutter side.
            if status == reqwest::StatusCode::FORBIDDEN {
                anyhow::bail!("HTTP_403_FORBIDDEN: Access denied (URL may have expired)");
            }
            if status == reqwest::StatusCode::GONE {
                anyhow::bail!("HTTP_410_GONE: Resource no longer available");
            }
            if status.as_u16() == 429 {
                // 429 is rate-limiting, not a permanent error — retry with backoff
                retry_429_count += 1;
                if retry_429_count > Self::MAX_429_RETRIES {
                    anyhow::bail!(
                        "HTTP_429_TOO_MANY_REQUESTS: Rate limited — too many requests (after {} retries)",
                        Self::MAX_429_RETRIES
                    );
                }
                let wait = Self::RETRY_429_BACKOFF_SECS[(retry_429_count - 1) as usize];
                eprintln!(
                    "⏳ HTTP 429 rate-limited — retrying in {}s (attempt {}/{})",
                    wait, retry_429_count, Self::MAX_429_RETRIES
                );
                let backoff_end = Instant::now() + Duration::from_secs(wait);
                while Instant::now() < backoff_end {
                    if self.is_cancelled() {
                        anyhow::bail!("Download cancelled during 429 backoff");
                    }
                    tokio::time::sleep(Duration::from_millis(200)).await;
                }
                continue; // retry the request
            }
            if status == reqwest::StatusCode::NOT_FOUND {
                anyhow::bail!("HTTP_404_NOT_FOUND: Resource not found");
            }
            if !status.is_success() && status != reqwest::StatusCode::PARTIAL_CONTENT {
                anyhow::bail!("HTTP_{}: {}", status.as_u16(), status.canonical_reason().unwrap_or("Unknown error"));
            }

            // Get total file size from content-length or content-range header
            let total_bytes = if status == reqwest::StatusCode::PARTIAL_CONTENT {
                response
                    .headers()
                    .get(header::CONTENT_RANGE)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| {
                        v.split('/').nth(1).and_then(|s| s.parse::<u64>().ok())
                    })
                    .unwrap_or(0)
            } else {
                response
                    .headers()
                    .get(header::CONTENT_LENGTH)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.parse::<u64>().ok())
                    .unwrap_or(0)
            };

            self.total_bytes.store(total_bytes, Ordering::SeqCst);

            // Open file: Create new if offset=0, or append if resuming/retrying
            let mut file = if current_offset > 0 {
                tokio::fs::OpenOptions::new()
                    .write(true)
                    .append(true)
                    .open(path_buf)
                    .await
                    .map_err(|e| anyhow::anyhow!("Failed to open file for resume: {}", e))?
            } else {
                File::create(path_buf).await?
            };

            // Stream download with token bucket rate limiting
            let mut stream = response.bytes_stream();
            let mut downloaded = current_offset;
            let mut last_progress_time = Instant::now();
            let mut stream_error: Option<String> = None;

            // Token bucket: track bytes in current 1-second window
            let mut window_start = Instant::now();
            let mut window_bytes: u64 = 0;

            // Sliding window: 5-second window for real-time speed measurement
            let mut speed_samples: VecDeque<SpeedSample> = VecDeque::new();

            while let Some(chunk) = stream.next().await {
                // Check if cancelled
                if self.is_cancelled() {
                    file.flush().await?;
                    drop(file);
                    tokio::fs::remove_file(path).await.ok();
                    anyhow::bail!("Download cancelled");
                }

                // Wait while paused
                while self.is_paused() {
                    if self.is_cancelled() {
                        file.flush().await?;
                        drop(file);
                        tokio::fs::remove_file(path).await.ok();
                        anyhow::bail!("Download cancelled while paused");
                    }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }

                match chunk {
                    Ok(data) => {
                        let chunk_len = data.len() as u64;
                        file.write_all(&data).await?;
                        downloaded += chunk_len;
                        self.downloaded_bytes.store(downloaded, Ordering::SeqCst);

                        // Token bucket rate limiting
                        if self.max_speed_bytes > 0 {
                            window_bytes += chunk_len;
                            let elapsed = window_start.elapsed();

                            if window_bytes >= self.max_speed_bytes {
                                // We've hit the limit for this window
                                if elapsed < Duration::from_secs(1) {
                                    let sleep_duration = Duration::from_secs(1) - elapsed;
                                    tokio::time::sleep(sleep_duration).await;
                                }
                                // Reset window
                                window_start = Instant::now();
                                window_bytes = 0;
                            } else if elapsed >= Duration::from_secs(1) {
                                // Window expired without hitting limit — reset
                                window_start = Instant::now();
                                window_bytes = 0;
                            }
                        }

                        // Record speed sample for sliding window
                        let now = Instant::now();
                        speed_samples.push_back(SpeedSample {
                            timestamp: now,
                            bytes: chunk_len,
                        });

                        // Prune samples older than 5 seconds
                        let cutoff = now - Duration::from_secs(5);
                        while speed_samples.front().map_or(false, |s| s.timestamp < cutoff) {
                            speed_samples.pop_front();
                        }

                        // Send progress update every 100ms
                        if now.duration_since(last_progress_time).as_millis() >= 100 {
                            let speed = Self::compute_sliding_speed(&speed_samples, now);

                            if let Some(ref tx) = self.progress_tx {
                                let _ = tx.send(DownloadProgress {
                                    total_bytes,
                                    downloaded_bytes: downloaded,
                                    speed,
                                });
                            }
                            last_progress_time = now;
                        }
                    }
                    Err(e) => {
                        // Stream error: save partial progress and break for retry.
                        // The file is flushed and closed below before backoff so
                        // Windows can delete it if the user cancels during retry.
                        stream_error = Some(format!("Stream error: {}", e));
                        break;
                    }
                }
            }

            file.flush().await?;
            drop(file);

            // If no stream error, download completed successfully
            if stream_error.is_none() {
                // Send final progress update
                if let Some(ref tx) = self.progress_tx {
                    let now = Instant::now();
                    let speed = Self::compute_sliding_speed(&speed_samples, now);

                    let _ = tx.send(DownloadProgress {
                        total_bytes,
                        downloaded_bytes: downloaded,
                        speed,
                    });
                }
                return Ok(());
            }

            // Stream error occurred — attempt retry
            stream_retry_count += 1;
            let error_msg = stream_error.unwrap();

            if stream_retry_count > MAX_STREAM_RETRIES {
                anyhow::bail!("{} (after {} retries)", error_msg, MAX_STREAM_RETRIES);
            }

            // Exponential backoff: 2s, 4s, 8s
            let backoff_secs = 1u64 << (stream_retry_count); // 2, 4, 8
            eprintln!(
                "⚠️ {} — retrying in {}s (attempt {}/{})",
                error_msg, backoff_secs, stream_retry_count, MAX_STREAM_RETRIES
            );

            // Wait with cancel check during backoff
            let backoff_end = Instant::now() + Duration::from_secs(backoff_secs);
            while Instant::now() < backoff_end {
                if self.is_cancelled() {
                    tokio::fs::remove_file(path).await.ok();
                    anyhow::bail!("Download cancelled during retry wait");
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }

            // Loop continues: reconnects with Range header from downloaded offset
        }
    }

    /// Extract the origin (scheme + host + trailing slash) from a URL for use as Referer.
    /// Returns None for malformed URLs.
    ///
    /// Example: "https://rr3---sn-xxx.googlevideo.com/videoplayback?..." → "https://rr3---sn-xxx.googlevideo.com/"
    pub fn extract_referer(url: &str) -> Option<String> {
        let scheme_end = url.find("://")?;
        let after_scheme = &url[scheme_end + 3..];
        let host_end = after_scheme.find('/').unwrap_or(after_scheme.len());
        let host = &after_scheme[..host_end];
        if host.is_empty() {
            return None;
        }
        let scheme = &url[..scheme_end];
        Some(format!("{scheme}://{host}/"))
    }

    /// Compute speed from sliding window samples (bytes/second)
    fn compute_sliding_speed(samples: &VecDeque<SpeedSample>, now: Instant) -> f64 {
        if samples.is_empty() {
            return 0.0;
        }
        let oldest = samples.front().unwrap().timestamp;
        let window_secs = now.duration_since(oldest).as_secs_f64().max(0.001);
        let total_bytes: u64 = samples.iter().map(|s| s.bytes).sum();
        total_bytes as f64 / window_secs
    }
}

impl Default for DownloadEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- Associated constants ---

    #[test]
    fn test_max_429_retries_is_3() {
        assert_eq!(DownloadEngine::MAX_429_RETRIES, 3);
    }

    #[test]
    fn test_429_backoff_first_is_5s() {
        assert_eq!(DownloadEngine::RETRY_429_BACKOFF_SECS[0], 5);
    }

    #[test]
    fn test_429_backoff_second_is_30s() {
        assert_eq!(DownloadEngine::RETRY_429_BACKOFF_SECS[1], 30);
    }

    #[test]
    fn test_429_backoff_third_is_60s() {
        assert_eq!(DownloadEngine::RETRY_429_BACKOFF_SECS[2], 60);
    }

    #[test]
    fn test_default_user_agent_not_empty() {
        assert!(!DownloadEngine::DEFAULT_USER_AGENT.is_empty());
    }

    #[test]
    fn test_default_user_agent_contains_mozilla() {
        assert!(DownloadEngine::DEFAULT_USER_AGENT.contains("Mozilla/5.0"));
    }

    // --- Initial state ---

    #[test]
    fn test_new_engine_not_paused() {
        let engine = DownloadEngine::new();
        assert!(!engine.is_paused());
    }

    #[test]
    fn test_new_engine_not_cancelled() {
        let engine = DownloadEngine::new();
        assert!(!engine.is_cancelled());
    }

    #[test]
    fn test_new_engine_downloaded_bytes_zero() {
        let engine = DownloadEngine::new();
        assert_eq!(engine.get_downloaded_bytes(), 0);
    }

    #[test]
    fn test_new_engine_total_bytes_zero() {
        let engine = DownloadEngine::new();
        assert_eq!(engine.get_total_bytes(), 0);
    }

    // --- Pause / resume / cancel ---

    #[test]
    fn test_pause_and_resume() {
        let engine = DownloadEngine::new();
        engine.pause();
        assert!(engine.is_paused());
        engine.resume();
        assert!(!engine.is_paused());
    }

    #[test]
    fn test_cancel_sets_cancelled() {
        let engine = DownloadEngine::new();
        engine.cancel();
        assert!(engine.is_cancelled());
    }

    // --- set_max_speed ---

    #[test]
    fn test_set_max_speed_no_panic() {
        let mut engine = DownloadEngine::new();
        engine.set_max_speed(1024 * 1024); // 1 MB/s
        // No panic = OK; default state unchanged
        assert!(!engine.is_paused());
    }

    // --- Per-request header rotation ---

    #[test]
    fn test_ua_pool_not_empty() {
        assert!(!DownloadEngine::UA_POOL.is_empty());
    }

    #[test]
    fn test_ua_pool_all_start_with_mozilla() {
        for ua in DownloadEngine::UA_POOL {
            assert!(ua.starts_with("Mozilla/5.0"), "UA should start with Mozilla/5.0: {}", ua);
        }
    }

    #[test]
    fn test_accept_language_pool_not_empty() {
        assert!(!DownloadEngine::ACCEPT_LANGUAGE_POOL.is_empty());
    }

    #[test]
    fn test_accept_language_pool_has_at_least_4_entries() {
        assert!(DownloadEngine::ACCEPT_LANGUAGE_POOL.len() >= 4);
    }

    #[test]
    fn test_request_count_starts_at_zero() {
        let engine = DownloadEngine::new();
        assert_eq!(engine.request_count.load(std::sync::atomic::Ordering::Relaxed), 0);
    }

    // --- extract_referer ---

    #[test]
    fn test_extract_referer_youtube() {
        let url = "https://rr3---sn-xxx.googlevideo.com/videoplayback?expire=123";
        let referer = DownloadEngine::extract_referer(url).unwrap();
        assert_eq!(referer, "https://rr3---sn-xxx.googlevideo.com/");
    }

    #[test]
    fn test_extract_referer_no_path() {
        let url = "https://example.com";
        let referer = DownloadEngine::extract_referer(url).unwrap();
        assert_eq!(referer, "https://example.com/");
    }

    #[test]
    fn test_extract_referer_http_scheme() {
        let url = "http://cdn.example.com/file.mp4?token=abc";
        let referer = DownloadEngine::extract_referer(url).unwrap();
        assert_eq!(referer, "http://cdn.example.com/");
    }

    #[test]
    fn test_extract_referer_returns_none_for_empty() {
        let referer = DownloadEngine::extract_referer("");
        assert!(referer.is_none());
    }
}
