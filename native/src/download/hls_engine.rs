/// HLS (HTTP Live Streaming) download engine
///
/// Handles m3u8 playlists: fetches the playlist, parses segment URLs,
/// downloads each .ts segment sequentially, and concatenates them into
/// the output file. Supports both master playlists (multi-quality) and
/// media playlists (direct segment lists).
use anyhow::Result;
use reqwest::{Client, header};
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc;

use super::config::DownloadConfig;
use super::engine::DownloadProgress;

pub struct HlsEngine {
    client: Client,
    is_paused: Arc<AtomicBool>,
    is_cancelled: Arc<AtomicBool>,
    downloaded_bytes: Arc<AtomicU64>,
    total_bytes: Arc<AtomicU64>,
    progress_tx: Option<mpsc::UnboundedSender<DownloadProgress>>,
}

impl HlsEngine {
    const DEFAULT_USER_AGENT: &'static str =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

    /// Create HLS engine with optional user-agent and proxy URL.
    pub fn with_options(user_agent: Option<String>, proxy_url: Option<String>) -> Self {
        Self::with_config(DownloadConfig {
            user_agent,
            proxy_url,
            ..Default::default()
        })
    }

    /// Create HLS engine from a full `DownloadConfig` (IDM mode — custom headers/cookies).
    pub fn with_config(config: DownloadConfig) -> Self {
        let client = config.build_client();

        Self {
            client,
            is_paused: Arc::new(AtomicBool::new(false)),
            is_cancelled: Arc::new(AtomicBool::new(false)),
            downloaded_bytes: Arc::new(AtomicU64::new(0)),
            total_bytes: Arc::new(AtomicU64::new(0)),
            progress_tx: None,
        }
    }

    pub fn set_progress_channel(&mut self, tx: mpsc::UnboundedSender<DownloadProgress>) {
        self.progress_tx = Some(tx);
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

    pub fn get_downloaded_bytes(&self) -> u64 {
        self.downloaded_bytes.load(Ordering::SeqCst)
    }

    pub fn get_total_bytes(&self) -> u64 {
        self.total_bytes.load(Ordering::SeqCst)
    }

    /// Resolve a segment URL relative to the playlist's base URL.
    ///
    /// - Absolute URLs (http/https) are returned unchanged.
    /// - Root-relative paths (`/path`) are resolved against the base host.
    /// - Relative paths are resolved against the base URL's directory.
    pub fn resolve_segment_url(base_url: &str, segment: &str) -> String {
        let segment = segment.trim();

        if segment.starts_with("http://") || segment.starts_with("https://") {
            return segment.to_string();
        }

        if segment.starts_with('/') {
            // Root-relative: extract scheme + host from base_url
            if let Some(scheme_end) = base_url.find("://") {
                let after_scheme = &base_url[scheme_end + 3..];
                let host_end = after_scheme.find('/').unwrap_or(after_scheme.len());
                let scheme = &base_url[..scheme_end];
                let host = &after_scheme[..host_end];
                return format!("{}://{}{}", scheme, host, segment);
            }
        }

        // Relative: resolve against base URL's directory (everything up to last '/')
        let base_dir = base_url
            .rfind('/')
            .map(|i| &base_url[..=i])
            .unwrap_or(base_url);
        format!("{}{}", base_dir, segment)
    }

    /// Parse a master playlist and return the URL of the highest-bandwidth variant.
    pub fn parse_master_playlist(base_url: &str, content: &str) -> Result<String> {
        let mut variants: Vec<(u64, String)> = Vec::new();
        let mut current_bandwidth: u64 = 0;
        let mut next_is_url = false;

        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() {
                continue;
            }

            if line.starts_with("#EXT-X-STREAM-INF") {
                current_bandwidth = Self::parse_bandwidth(line).unwrap_or(0);
                next_is_url = true;
            } else if next_is_url && !line.starts_with('#') {
                variants.push((
                    current_bandwidth,
                    Self::resolve_segment_url(base_url, line),
                ));
                next_is_url = false;
            }
        }

        if variants.is_empty() {
            anyhow::bail!("Master playlist has no stream variants");
        }

        // Highest bandwidth = best quality
        variants.sort_by(|a, b| b.0.cmp(&a.0));
        Ok(variants[0].1.clone())
    }

    /// Parse a media playlist and return all segment URLs in order.
    pub fn parse_media_playlist(base_url: &str, content: &str) -> Result<Vec<String>> {
        let segments: Vec<String> = content
            .lines()
            .map(|l| l.trim())
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .map(|l| Self::resolve_segment_url(base_url, l))
            .collect();

        if segments.is_empty() {
            anyhow::bail!("Media playlist contains no segments");
        }

        Ok(segments)
    }

    /// Extract BANDWIDTH value from an #EXT-X-STREAM-INF tag line.
    /// Strips the `#EXT-X-STREAM-INF:` prefix before parsing attributes.
    fn parse_bandwidth(line: &str) -> Option<u64> {
        // Strip tag prefix: "#EXT-X-STREAM-INF:ATTR1=val,ATTR2=val" → "ATTR1=val,ATTR2=val"
        let attrs = line.find(':').map(|i| &line[i + 1..]).unwrap_or(line);
        attrs.split(',').find_map(|attr| {
            let attr = attr.trim();
            if let Some(val) = attr.strip_prefix("BANDWIDTH=") {
                val.parse::<u64>().ok()
            } else {
                None
            }
        })
    }

    /// Fetch and resolve segment list from an m3u8 URL.
    /// Handles master → media playlist chain (one level of redirect).
    async fn fetch_segments(&self, url: &str) -> Result<Vec<String>> {
        let response = self.client.get(url).send().await
            .map_err(|e| anyhow::anyhow!("Failed to fetch playlist: {}", e))?;

        if !response.status().is_success() {
            anyhow::bail!("Playlist fetch HTTP {}", response.status());
        }

        let content = response.text().await?;

        // Master playlist: follow to best-quality variant
        if content.contains("#EXT-X-STREAM-INF") {
            let variant_url = Self::parse_master_playlist(url, &content)?;
            eprintln!("📋 [HLS] Master playlist → variant: {}", variant_url);

            let media_resp = self.client.get(&variant_url).send().await
                .map_err(|e| anyhow::anyhow!("Failed to fetch media playlist: {}", e))?;

            if !media_resp.status().is_success() {
                anyhow::bail!("Media playlist fetch HTTP {}", media_resp.status());
            }

            let media_content = media_resp.text().await?;
            return Self::parse_media_playlist(&variant_url, &media_content);
        }

        // Media playlist: parse directly
        Self::parse_media_playlist(url, &content)
    }

    /// Download a single segment, retrying up to `max_retries` times on error.
    async fn download_segment(&self, url: &str, max_retries: u32) -> Result<Vec<u8>> {
        let mut attempt = 0u32;
        loop {
            match self.client.get(url).send().await {
                Ok(resp) if resp.status().is_success() => {
                    return resp.bytes().await
                        .map(|b| b.to_vec())
                        .map_err(|e| anyhow::anyhow!("Read segment body: {}", e));
                }
                Ok(resp) => {
                    if attempt >= max_retries {
                        anyhow::bail!("HTTP {} for segment", resp.status());
                    }
                }
                Err(e) => {
                    if attempt >= max_retries {
                        anyhow::bail!("Network error after {} retries: {}", max_retries, e);
                    }
                }
            }
            attempt += 1;
            let backoff = std::time::Duration::from_secs(attempt as u64);
            tokio::time::sleep(backoff).await;
        }
    }

    /// Download HLS stream: parse playlist → download segments → concatenate output.
    pub async fn download_hls(&mut self, url: &str, output_path: &str) -> Result<()> {
        // Reset state
        self.is_cancelled.store(false, Ordering::SeqCst);
        self.is_paused.store(false, Ordering::SeqCst);
        self.downloaded_bytes.store(0, Ordering::SeqCst);
        self.total_bytes.store(0, Ordering::SeqCst);

        let segments = self.fetch_segments(url).await?;
        let total = segments.len();

        if total == 0 {
            anyhow::bail!("No segments found in HLS playlist");
        }

        eprintln!("📋 [HLS] {} segments to download", total);

        // Create output file
        let path = Path::new(output_path);
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let mut out = tokio::fs::File::create(path).await
            .map_err(|e| anyhow::anyhow!("Cannot create output file {}: {}", output_path, e))?;

        // Download and concatenate each segment
        for (idx, seg_url) in segments.iter().enumerate() {
            // Cancel check
            if self.is_cancelled.load(Ordering::SeqCst) {
                out.flush().await?;
                tokio::fs::remove_file(path).await.ok();
                anyhow::bail!("Download cancelled");
            }

            // Pause loop
            while self.is_paused.load(Ordering::SeqCst) {
                if self.is_cancelled.load(Ordering::SeqCst) {
                    out.flush().await?;
                    tokio::fs::remove_file(path).await.ok();
                    anyhow::bail!("Download cancelled while paused");
                }
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            }

            let data: Vec<u8> = self
                .download_segment(seg_url, 3)
                .await
                .map_err(|e| anyhow::anyhow!("Segment {}/{} failed: {}", idx + 1, total, e))?;

            let seg_len = data.len() as u64;
            out.write_all(&data).await?;

            let new_downloaded = self.downloaded_bytes.fetch_add(seg_len, Ordering::SeqCst) + seg_len;

            // Send progress update
            if let Some(ref tx) = self.progress_tx {
                let _ = tx.send(DownloadProgress {
                    total_bytes: 0, // stream total unknown until all segments fetched
                    downloaded_bytes: new_downloaded,
                    speed: 0.0,
                });
            }

            eprintln!(
                "📥 [HLS] {}/{} ({} bytes, {} total)",
                idx + 1,
                total,
                seg_len,
                new_downloaded
            );
        }

        out.flush().await?;

        let final_bytes = self.downloaded_bytes.load(Ordering::SeqCst);

        // Set total_bytes = downloaded now that we know the full size
        self.total_bytes.store(final_bytes, Ordering::SeqCst);

        // Final progress event
        if let Some(ref tx) = self.progress_tx {
            let _ = tx.send(DownloadProgress {
                total_bytes: final_bytes,
                downloaded_bytes: final_bytes,
                speed: 0.0,
            });
        }

        eprintln!(
            "✅ [HLS] Download complete: {} segments, {} bytes",
            total,
            final_bytes
        );
        Ok(())
    }
}

// ── Unit tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> HlsEngine {
        HlsEngine::with_options(None, None)
    }

    // --- resolve_segment_url ---

    #[test]
    fn resolve_absolute_url_unchanged() {
        let result = HlsEngine::resolve_segment_url(
            "https://cdn.example.com/stream/index.m3u8",
            "https://other.cdn.com/seg0.ts",
        );
        assert_eq!(result, "https://other.cdn.com/seg0.ts");
    }

    #[test]
    fn resolve_root_relative_url() {
        let result = HlsEngine::resolve_segment_url(
            "https://cdn.example.com/hls/stream.m3u8",
            "/segments/seg0.ts",
        );
        assert_eq!(result, "https://cdn.example.com/segments/seg0.ts");
    }

    #[test]
    fn resolve_relative_url_same_directory() {
        let result = HlsEngine::resolve_segment_url(
            "https://cdn.example.com/hls/stream.m3u8",
            "seg0.ts",
        );
        assert_eq!(result, "https://cdn.example.com/hls/seg0.ts");
    }

    #[test]
    fn resolve_relative_url_subdirectory() {
        let result = HlsEngine::resolve_segment_url(
            "https://cdn.example.com/hls/index.m3u8",
            "chunks/seg0.ts",
        );
        assert_eq!(result, "https://cdn.example.com/hls/chunks/seg0.ts");
    }

    // --- parse_media_playlist ---

    #[test]
    fn parse_media_playlist_basic() {
        let content = "\
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.000,
seg0.ts
#EXTINF:10.000,
seg1.ts
#EXTINF:8.500,
seg2.ts
#EXT-X-ENDLIST";
        let segments =
            HlsEngine::parse_media_playlist("https://cdn.example.com/hls/index.m3u8", content)
                .unwrap();
        assert_eq!(segments.len(), 3);
        assert_eq!(segments[0], "https://cdn.example.com/hls/seg0.ts");
        assert_eq!(segments[1], "https://cdn.example.com/hls/seg1.ts");
        assert_eq!(segments[2], "https://cdn.example.com/hls/seg2.ts");
    }

    #[test]
    fn parse_media_playlist_absolute_urls() {
        let content = "\
#EXTM3U
#EXTINF:10.000,
https://other.cdn.com/seg0.ts
#EXTINF:10.000,
https://other.cdn.com/seg1.ts
#EXT-X-ENDLIST";
        let segments =
            HlsEngine::parse_media_playlist("https://cdn.example.com/stream.m3u8", content)
                .unwrap();
        assert_eq!(segments.len(), 2);
        assert_eq!(segments[0], "https://other.cdn.com/seg0.ts");
    }

    #[test]
    fn parse_media_playlist_empty_fails() {
        let content = "#EXTM3U\n#EXT-X-ENDLIST\n";
        let result =
            HlsEngine::parse_media_playlist("https://cdn.example.com/stream.m3u8", content);
        assert!(result.is_err());
    }

    // --- parse_master_playlist ---

    #[test]
    fn parse_master_playlist_selects_highest_bandwidth() {
        let content = "\
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
high/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480
mid/stream.m3u8";
        let url =
            HlsEngine::parse_master_playlist("https://cdn.example.com/master.m3u8", content)
                .unwrap();
        assert!(url.contains("high/stream.m3u8"), "Expected high-bandwidth variant, got: {}", url);
    }

    #[test]
    fn parse_master_playlist_no_variants_fails() {
        let content = "#EXTM3U\n";
        let result =
            HlsEngine::parse_master_playlist("https://cdn.example.com/master.m3u8", content);
        assert!(result.is_err());
    }

    // --- parse_bandwidth ---

    #[test]
    fn parse_bandwidth_extracts_value() {
        let line = "#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS=\"avc1\",RESOLUTION=1280x720";
        assert_eq!(HlsEngine::parse_bandwidth(line), Some(3_000_000));
    }

    #[test]
    fn parse_bandwidth_missing_returns_none() {
        let line = "#EXT-X-STREAM-INF:CODECS=\"avc1\"";
        assert_eq!(HlsEngine::parse_bandwidth(line), None);
    }
}
