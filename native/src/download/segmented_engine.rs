/// Multi-segment parallel download engine
/// Splits a file into N byte ranges, downloads each concurrently via tokio tasks,
/// then concatenates the segments into the final output file.
use anyhow::Result;
use reqwest::{Client, header};
use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

use super::config::DownloadConfig;
use super::engine::DownloadProgress;

/// A byte range for one segment: [start, end] inclusive
#[derive(Debug, Clone)]
pub struct SegmentRange {
    pub index: u32,
    pub start: u64,
    pub end: u64, // inclusive
}

pub struct SegmentedEngine {
    client: Client,
    num_segments: u32,
    is_paused: Arc<AtomicBool>,
    is_cancelled: Arc<AtomicBool>,
    downloaded_bytes: Arc<AtomicU64>, // aggregate across all segments
    total_bytes: Arc<AtomicU64>,
    max_speed_bytes: u64, // 0 = unlimited
    progress_tx: Option<mpsc::UnboundedSender<DownloadProgress>>,
}

impl SegmentedEngine {
    /// Default User-Agent used when none is provided.
    const DEFAULT_USER_AGENT: &'static str =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

    pub fn new(num_segments: u32) -> Self {
        Self::with_user_agent(num_segments, None)
    }

    pub fn with_user_agent(num_segments: u32, user_agent: Option<String>) -> Self {
        Self::with_options(num_segments, user_agent, None)
    }

    /// Create engine with user-agent and optional HTTP proxy.
    pub fn with_options(num_segments: u32, user_agent: Option<String>, proxy_url: Option<String>) -> Self {
        Self::with_config(num_segments, DownloadConfig {
            user_agent,
            proxy_url,
            ..Default::default()
        })
    }

    /// Create engine from a full `DownloadConfig` (IDM mode — custom headers/cookies).
    pub fn with_config(num_segments: u32, config: DownloadConfig) -> Self {
        let num = num_segments.clamp(1, 16);
        let client = config.build_client();

        Self {
            client,
            num_segments: num,
            is_paused: Arc::new(AtomicBool::new(false)),
            is_cancelled: Arc::new(AtomicBool::new(false)),
            downloaded_bytes: Arc::new(AtomicU64::new(0)),
            total_bytes: Arc::new(AtomicU64::new(0)),
            max_speed_bytes: 0,
            progress_tx: None,
        }
    }

    pub fn set_progress_channel(&mut self, tx: mpsc::UnboundedSender<DownloadProgress>) {
        self.progress_tx = Some(tx);
    }

    pub fn set_max_speed(&mut self, max_speed_bytes: u64) {
        self.max_speed_bytes = max_speed_bytes;
    }

    pub fn pause(&self) {
        self.is_paused.store(true, Ordering::SeqCst);
    }

    pub fn resume(&self) {
        self.is_paused.store(false, Ordering::SeqCst);
    }

    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_paused(&self) -> bool {
        self.is_paused.load(Ordering::SeqCst)
    }

    pub fn is_cancelled(&self) -> bool {
        self.is_cancelled.load(Ordering::SeqCst)
    }

    pub fn get_downloaded_bytes(&self) -> u64 {
        self.downloaded_bytes.load(Ordering::SeqCst)
    }

    pub fn get_total_bytes(&self) -> u64 {
        self.total_bytes.load(Ordering::SeqCst)
    }

    /// Map bandwidth (bytes/sec) to an optimal segment count.
    ///
    /// Tiers mirror `AdaptiveSegmentService.computeOptimalSegments()` in Dart:
    /// - < 5 MB/s  → 2 segments
    /// - 5–20 MB/s → 4 segments
    /// - 20–50 MB/s→ 8 segments
    /// - > 50 MB/s → 16 segments
    pub fn adaptive_compute_segments(bandwidth_bps: u64) -> u32 {
        const MBPS_5: u64 = 5 * 1024 * 1024;
        const MBPS_20: u64 = 20 * 1024 * 1024;
        const MBPS_50: u64 = 50 * 1024 * 1024;
        if bandwidth_bps < MBPS_5 { return 2; }
        if bandwidth_bps < MBPS_20 { return 4; }
        if bandwidth_bps < MBPS_50 { return 8; }
        16
    }

    /// Compute segment byte ranges from total file size.
    /// Returns Vec of (start, end) inclusive ranges covering the entire file.
    pub fn compute_segments(total_bytes: u64, num_segments: u32) -> Vec<SegmentRange> {
        if total_bytes == 0 || num_segments == 0 {
            return vec![];
        }

        let n = (num_segments as u64).min(total_bytes);
        let chunk_size = total_bytes / n;
        let remainder = total_bytes % n;

        let mut segments = Vec::with_capacity(n as usize);
        let mut offset: u64 = 0;

        for i in 0..n {
            // Distribute remainder across first `remainder` segments
            let extra = if i < remainder { 1 } else { 0 };
            let size = chunk_size + extra;
            let end = offset + size - 1;

            segments.push(SegmentRange {
                index: i as u32,
                start: offset,
                end,
            });

            offset = end + 1;
        }

        segments
    }

    /// Download file using multiple segments (parallel byte-range requests).
    /// Falls back to single-stream if server doesn't support Range or file < 1MB.
    pub async fn download_segmented(&mut self, url: &str, path: &str) -> Result<()> {
        // Reset state
        self.is_paused.store(false, Ordering::SeqCst);
        self.is_cancelled.store(false, Ordering::SeqCst);
        self.downloaded_bytes.store(0, Ordering::SeqCst);

        // Step 1: HEAD request to check Accept-Ranges and Content-Length
        let head_resp = self.client.head(url)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("HEAD request failed: {}", e))?;

        let supports_range = head_resp
            .headers()
            .get(header::ACCEPT_RANGES)
            .and_then(|v| v.to_str().ok())
            .map(|v| v.contains("bytes"))
            .unwrap_or(false);

        let content_length = head_resp
            .headers()
            .get(header::CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0);

        // Fallback to single-stream if no Range support or file too small (<1MB)
        const MIN_SEGMENTED_SIZE: u64 = 1_048_576; // 1MB
        if !supports_range || content_length < MIN_SEGMENTED_SIZE || self.num_segments <= 1 {
            return self.download_single_stream(url, path).await;
        }

        self.total_bytes.store(content_length, Ordering::SeqCst);

        let segments = Self::compute_segments(content_length, self.num_segments);
        let path_buf = PathBuf::from(path);

        // Create parent directories
        if let Some(parent) = path_buf.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        // Check for existing .part files (resume support)
        let mut segment_offsets: Vec<u64> = Vec::with_capacity(segments.len());
        for seg in &segments {
            let part_path = Self::part_path(&path_buf, seg.index);
            if part_path.exists() {
                let meta = tokio::fs::metadata(&part_path).await?;
                let existing_bytes = meta.len();
                let segment_size = seg.end - seg.start + 1;
                if existing_bytes < segment_size {
                    segment_offsets.push(existing_bytes);
                } else {
                    // Segment already complete
                    segment_offsets.push(segment_size);
                }
            } else {
                segment_offsets.push(0);
            }
        }

        // Set initial downloaded bytes from existing parts
        let initial_downloaded: u64 = segment_offsets.iter().sum();
        self.downloaded_bytes.store(initial_downloaded, Ordering::SeqCst);

        // Step 2: Spawn segment download tasks
        let mut handles = Vec::with_capacity(segments.len());

        // Per-segment speed limit
        let per_segment_speed = if self.max_speed_bytes > 0 {
            (self.max_speed_bytes / segments.len() as u64).max(1)
        } else {
            0
        };

        // Start progress reporter
        let progress_tx = self.progress_tx.clone();
        let downloaded_ref = Arc::clone(&self.downloaded_bytes);
        let total_ref = Arc::clone(&self.total_bytes);
        let cancelled_ref = Arc::clone(&self.is_cancelled);
        let progress_handle = tokio::spawn(async move {
            let mut last_bytes: u64 = 0;
            let mut last_time = Instant::now();
            loop {
                tokio::time::sleep(Duration::from_millis(200)).await;
                if cancelled_ref.load(Ordering::SeqCst) {
                    break;
                }
                let now = Instant::now();
                let current = downloaded_ref.load(Ordering::SeqCst);
                let total = total_ref.load(Ordering::SeqCst);
                let elapsed = now.duration_since(last_time).as_secs_f64().max(0.001);
                let speed = (current.saturating_sub(last_bytes)) as f64 / elapsed;
                last_bytes = current;
                last_time = now;

                if let Some(ref tx) = progress_tx {
                    let _ = tx.send(DownloadProgress {
                        total_bytes: total,
                        downloaded_bytes: current,
                        speed,
                    });
                }

                // Stop if download completed
                if current >= total && total > 0 {
                    break;
                }
            }
        });

        for (seg, &offset) in segments.iter().zip(segment_offsets.iter()) {
            let segment_size = seg.end - seg.start + 1;
            if offset >= segment_size {
                // Segment already complete, skip
                continue;
            }

            let client = self.client.clone();
            let url = url.to_string();
            let part_path = Self::part_path(&path_buf, seg.index);
            let range_start = seg.start + offset;
            let range_end = seg.end;
            let is_paused = Arc::clone(&self.is_paused);
            let is_cancelled = Arc::clone(&self.is_cancelled);
            let downloaded_bytes = Arc::clone(&self.downloaded_bytes);
            let max_speed = per_segment_speed;

            let handle = tokio::spawn(async move {
                Self::download_segment(
                    client,
                    &url,
                    &part_path,
                    range_start,
                    range_end,
                    offset > 0, // append mode if resuming
                    is_paused,
                    is_cancelled,
                    downloaded_bytes,
                    max_speed,
                ).await
            });

            handles.push(handle);
        }

        // Wait for all segments
        let mut any_error: Option<String> = None;
        for handle in handles {
            match handle.await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    if any_error.is_none() {
                        any_error = Some(e.to_string());
                    }
                    // Cancel remaining segments
                    self.is_cancelled.store(true, Ordering::SeqCst);
                }
                Err(e) => {
                    if any_error.is_none() {
                        any_error = Some(format!("Segment task panicked: {}", e));
                    }
                    self.is_cancelled.store(true, Ordering::SeqCst);
                }
            }
        }

        // Stop progress reporter
        progress_handle.abort();

        if let Some(err) = any_error {
            anyhow::bail!("Segmented download failed: {}", err);
        }

        // Step 3: Concatenate .part files into final output
        self.concatenate_segments(&path_buf, &segments).await?;

        // Step 4: Cleanup .part files
        for seg in &segments {
            let part = Self::part_path(&path_buf, seg.index);
            tokio::fs::remove_file(&part).await.ok();
        }

        // Send final progress
        if let Some(ref tx) = self.progress_tx {
            let _ = tx.send(DownloadProgress {
                total_bytes: content_length,
                downloaded_bytes: content_length,
                speed: 0.0,
            });
        }

        Ok(())
    }

    /// Download a single segment with Range header
    async fn download_segment(
        client: Client,
        url: &str,
        part_path: &Path,
        range_start: u64,
        range_end: u64,
        append: bool,
        is_paused: Arc<AtomicBool>,
        is_cancelled: Arc<AtomicBool>,
        global_downloaded: Arc<AtomicU64>,
        max_speed_bytes: u64,
    ) -> Result<()> {
        use futures_util::StreamExt;

        const MAX_RETRIES: u32 = 3;
        let mut retry_count: u32 = 0;
        let mut bytes_written: u64 = if append {
            // Read existing file size
            if part_path.exists() {
                tokio::fs::metadata(part_path).await?.len()
            } else {
                0
            }
        } else {
            0
        };

        loop {
            let current_start = range_start + bytes_written;
            if current_start > range_end {
                return Ok(()); // Segment complete
            }

            let range_header = format!("bytes={}-{}", current_start, range_end);
            let response = client.get(url)
                .header(header::RANGE, &range_header)
                .send()
                .await
                .map_err(|e| anyhow::anyhow!("Segment request failed: {}", e))?;

            let status = response.status();
            if status == reqwest::StatusCode::FORBIDDEN || status == reqwest::StatusCode::NOT_FOUND {
                anyhow::bail!("HTTP {}", status);
            }
            if !status.is_success() && status != reqwest::StatusCode::PARTIAL_CONTENT {
                anyhow::bail!("HTTP {}", status);
            }

            // Open file
            let mut file = if bytes_written > 0 {
                tokio::fs::OpenOptions::new()
                    .write(true)
                    .append(true)
                    .open(part_path)
                    .await?
            } else {
                File::create(part_path).await?
            };

            let mut stream = response.bytes_stream();
            let mut stream_error: Option<String> = None;

            // Token bucket for rate limiting
            let mut window_start = Instant::now();
            let mut window_bytes: u64 = 0;

            while let Some(chunk) = stream.next().await {
                // Check cancelled
                if is_cancelled.load(Ordering::SeqCst) {
                    file.flush().await?;
                    anyhow::bail!("Download cancelled");
                }

                // Wait while paused
                while is_paused.load(Ordering::SeqCst) {
                    if is_cancelled.load(Ordering::SeqCst) {
                        file.flush().await?;
                        anyhow::bail!("Download cancelled while paused");
                    }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }

                match chunk {
                    Ok(data) => {
                        let chunk_len = data.len() as u64;
                        file.write_all(&data).await?;
                        bytes_written += chunk_len;
                        global_downloaded.fetch_add(chunk_len, Ordering::SeqCst);

                        // Token bucket rate limiting
                        if max_speed_bytes > 0 {
                            window_bytes += chunk_len;
                            let elapsed = window_start.elapsed();
                            if window_bytes >= max_speed_bytes {
                                if elapsed < Duration::from_secs(1) {
                                    let sleep_dur = Duration::from_secs(1) - elapsed;
                                    tokio::time::sleep(sleep_dur).await;
                                }
                                window_start = Instant::now();
                                window_bytes = 0;
                            } else if elapsed >= Duration::from_secs(1) {
                                window_start = Instant::now();
                                window_bytes = 0;
                            }
                        }
                    }
                    Err(e) => {
                        file.flush().await?;
                        stream_error = Some(format!("Stream error: {}", e));
                        break;
                    }
                }
            }

            if stream_error.is_none() {
                file.flush().await?;
                return Ok(());
            }

            // Retry on stream error
            retry_count += 1;
            let error_msg = stream_error.unwrap();
            if retry_count > MAX_RETRIES {
                anyhow::bail!("{} (after {} retries)", error_msg, MAX_RETRIES);
            }

            let backoff_secs = 1u64 << retry_count; // 2, 4, 8
            let backoff_end = Instant::now() + Duration::from_secs(backoff_secs);
            while Instant::now() < backoff_end {
                if is_cancelled.load(Ordering::SeqCst) {
                    anyhow::bail!("Download cancelled during retry");
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        }
    }

    /// Concatenate .part files into the final output
    async fn concatenate_segments(&self, output_path: &Path, segments: &[SegmentRange]) -> Result<()> {
        let mut output_file = File::create(output_path).await?;
        let mut buf = vec![0u8; 64 * 1024]; // 64KB buffer

        for seg in segments {
            let part = Self::part_path(output_path, seg.index);
            let mut part_file = File::open(&part).await
                .map_err(|e| anyhow::anyhow!("Failed to open part {}: {}", seg.index, e))?;

            loop {
                let n = part_file.read(&mut buf).await?;
                if n == 0 {
                    break;
                }
                output_file.write_all(&buf[..n]).await?;
            }
        }

        output_file.flush().await?;
        Ok(())
    }

    /// Fallback: single-stream download (delegates to simple GET + write)
    async fn download_single_stream(&mut self, url: &str, path: &str) -> Result<()> {
        use futures_util::StreamExt;

        self.downloaded_bytes.store(0, Ordering::SeqCst);

        let response = self.client.get(url)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Request failed: {}", e))?;

        let status = response.status();
        if !status.is_success() {
            anyhow::bail!("HTTP {}", status);
        }

        let total = response
            .headers()
            .get(header::CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0);
        self.total_bytes.store(total, Ordering::SeqCst);

        let path_buf = Path::new(path);
        if let Some(parent) = path_buf.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let mut file = File::create(path_buf).await?;
        let mut stream = response.bytes_stream();
        let mut downloaded: u64 = 0;
        let mut last_progress = Instant::now();
        let mut speed_samples: VecDeque<(Instant, u64)> = VecDeque::new();

        while let Some(chunk) = stream.next().await {
            if self.is_cancelled() {
                file.flush().await?;
                tokio::fs::remove_file(path).await.ok();
                anyhow::bail!("Download cancelled");
            }

            while self.is_paused() {
                if self.is_cancelled() {
                    file.flush().await?;
                    tokio::fs::remove_file(path).await.ok();
                    anyhow::bail!("Download cancelled while paused");
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }

            match chunk {
                Ok(data) => {
                    let len = data.len() as u64;
                    file.write_all(&data).await?;
                    downloaded += len;
                    self.downloaded_bytes.store(downloaded, Ordering::SeqCst);

                    let now = Instant::now();
                    speed_samples.push_back((now, len));
                    let cutoff = now - Duration::from_secs(5);
                    while speed_samples.front().map_or(false, |s| s.0 < cutoff) {
                        speed_samples.pop_front();
                    }

                    if now.duration_since(last_progress).as_millis() >= 200 {
                        let speed = if speed_samples.is_empty() {
                            0.0
                        } else {
                            let oldest = speed_samples.front().unwrap().0;
                            let window = now.duration_since(oldest).as_secs_f64().max(0.001);
                            let total_sample_bytes: u64 = speed_samples.iter().map(|s| s.1).sum();
                            total_sample_bytes as f64 / window
                        };

                        if let Some(ref tx) = self.progress_tx {
                            let _ = tx.send(DownloadProgress {
                                total_bytes: total,
                                downloaded_bytes: downloaded,
                                speed,
                            });
                        }
                        last_progress = now;
                    }
                }
                Err(e) => {
                    file.flush().await?;
                    anyhow::bail!("Stream error: {}", e);
                }
            }
        }

        file.flush().await?;

        if let Some(ref tx) = self.progress_tx {
            let _ = tx.send(DownloadProgress {
                total_bytes: total,
                downloaded_bytes: downloaded,
                speed: 0.0,
            });
        }

        Ok(())
    }

    /// Get the .part file path for a segment index
    fn part_path(base_path: &Path, index: u32) -> PathBuf {
        let mut part = base_path.as_os_str().to_os_string();
        part.push(format!(".part{}", index));
        PathBuf::from(part)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_segments_basic() {
        let segs = SegmentedEngine::compute_segments(1000, 4);
        assert_eq!(segs.len(), 4);
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs[0].end, 249);
        assert_eq!(segs[1].start, 250);
        assert_eq!(segs[1].end, 499);
        assert_eq!(segs[2].start, 500);
        assert_eq!(segs[2].end, 749);
        assert_eq!(segs[3].start, 750);
        assert_eq!(segs[3].end, 999);
    }

    #[test]
    fn test_compute_segments_with_remainder() {
        let segs = SegmentedEngine::compute_segments(10, 3);
        assert_eq!(segs.len(), 3);
        // 10 / 3 = 3 remainder 1 → first segment gets +1
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs[0].end, 3); // 4 bytes
        assert_eq!(segs[1].start, 4);
        assert_eq!(segs[1].end, 6); // 3 bytes
        assert_eq!(segs[2].start, 7);
        assert_eq!(segs[2].end, 9); // 3 bytes
    }

    #[test]
    fn test_compute_segments_single() {
        let segs = SegmentedEngine::compute_segments(500, 1);
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs[0].end, 499);
    }

    #[test]
    fn test_compute_segments_zero_bytes() {
        let segs = SegmentedEngine::compute_segments(0, 4);
        assert_eq!(segs.len(), 0);
    }

    #[test]
    fn test_compute_segments_zero_segments() {
        let segs = SegmentedEngine::compute_segments(1000, 0);
        assert_eq!(segs.len(), 0);
    }

    #[test]
    fn test_compute_segments_more_than_bytes() {
        // 5 bytes but 10 segments → clamped to 5 segments of 1 byte each
        let segs = SegmentedEngine::compute_segments(5, 10);
        assert_eq!(segs.len(), 5);
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs[0].end, 0);
        assert_eq!(segs[4].start, 4);
        assert_eq!(segs[4].end, 4);
    }

    #[test]
    fn test_compute_segments_no_gaps_no_overlaps() {
        let total: u64 = 9999;
        let segs = SegmentedEngine::compute_segments(total, 7);
        // Verify no gaps and no overlaps
        for i in 1..segs.len() {
            assert_eq!(segs[i].start, segs[i - 1].end + 1, "Gap between segment {} and {}", i - 1, i);
        }
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs.last().unwrap().end, total - 1);
        // Verify total coverage
        let total_covered: u64 = segs.iter().map(|s| s.end - s.start + 1).sum();
        assert_eq!(total_covered, total);
    }

    #[test]
    fn test_compute_segments_exact_division() {
        let segs = SegmentedEngine::compute_segments(16, 4);
        assert_eq!(segs.len(), 4);
        for seg in &segs {
            assert_eq!(seg.end - seg.start + 1, 4); // Each segment exactly 4 bytes
        }
    }

    #[test]
    fn test_compute_segments_large_file() {
        let total: u64 = 1_073_741_824; // 1GB
        let segs = SegmentedEngine::compute_segments(total, 16);
        assert_eq!(segs.len(), 16);
        assert_eq!(segs[0].start, 0);
        assert_eq!(segs.last().unwrap().end, total - 1);
        let total_covered: u64 = segs.iter().map(|s| s.end - s.start + 1).sum();
        assert_eq!(total_covered, total);
    }

    #[test]
    fn test_part_path() {
        let base = PathBuf::from("/tmp/video.mp4");
        assert_eq!(SegmentedEngine::part_path(&base, 0), PathBuf::from("/tmp/video.mp4.part0"));
        assert_eq!(SegmentedEngine::part_path(&base, 3), PathBuf::from("/tmp/video.mp4.part3"));
    }

    // --- adaptive_compute_segments tests ---

    #[test]
    fn test_adaptive_segments_zero_bandwidth() {
        // 0 bps (no signal) → below 5 MB/s tier → 2 segments
        assert_eq!(SegmentedEngine::adaptive_compute_segments(0), 2);
    }

    #[test]
    fn test_adaptive_segments_below_5mbps() {
        // 1 MB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(1 * 1024 * 1024), 2);
        // 4.99 MB/s (just under threshold)
        assert_eq!(SegmentedEngine::adaptive_compute_segments(5 * 1024 * 1024 - 1), 2);
    }

    #[test]
    fn test_adaptive_segments_at_5mbps_boundary() {
        // Exactly 5 MB/s → transitions to 4-segment tier
        assert_eq!(SegmentedEngine::adaptive_compute_segments(5 * 1024 * 1024), 4);
    }

    #[test]
    fn test_adaptive_segments_5_to_20mbps() {
        // 10 MB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(10 * 1024 * 1024), 4);
        // 19.9 MB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(20 * 1024 * 1024 - 1), 4);
    }

    #[test]
    fn test_adaptive_segments_at_20mbps_boundary() {
        // Exactly 20 MB/s → transitions to 8-segment tier
        assert_eq!(SegmentedEngine::adaptive_compute_segments(20 * 1024 * 1024), 8);
    }

    #[test]
    fn test_adaptive_segments_20_to_50mbps() {
        // 35 MB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(35 * 1024 * 1024), 8);
        // 49.9 MB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(50 * 1024 * 1024 - 1), 8);
    }

    #[test]
    fn test_adaptive_segments_at_50mbps_boundary() {
        // Exactly 50 MB/s → transitions to 16-segment tier
        assert_eq!(SegmentedEngine::adaptive_compute_segments(50 * 1024 * 1024), 16);
    }

    #[test]
    fn test_adaptive_segments_above_50mbps() {
        // 100 MB/s (gigabit connection)
        assert_eq!(SegmentedEngine::adaptive_compute_segments(100 * 1024 * 1024), 16);
        // 1 GB/s
        assert_eq!(SegmentedEngine::adaptive_compute_segments(1024 * 1024 * 1024), 16);
    }
}
