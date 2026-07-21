/// Main API bridge for Flutter
/// This file contains all Rust functions exposed to Dart via flutter_rust_bridge

use crate::download::config::DownloadConfig;
use crate::download::engine::DownloadEngine;
use crate::filesystem::scanner::scan_directory;
use crate::ytdlp::executor::{YtDlpConfig, YtDlpExecutor};
use crate::ytdlp::parser::{ChannelInfo, PlaylistInfo, PlaylistVideo, YtDlpFormat, YtDlpVideoInfo, YtDlpStatus, YouTubeSearchResult};
use futures_util::StreamExt;

/// Get system information (test function)
pub fn get_system_info() -> String {
    let os = std::env::consts::OS;
    let arch = std::env::consts::ARCH;
    let version = env!("CARGO_PKG_VERSION");

    format!(
        "Native Bridge\nOS: {}\nArch: {}\nVersion: {}",
        os, arch, version
    )
}

/// Initialize Rust-side Sentry telemetry. FRB-visible wrapper around
/// [`crate::telemetry::init_telemetry`].
///
/// `rust_input: "crate::api"` in flutter_rust_bridge.yaml means FRB only
/// generates Dart bindings for `pub fn`s declared in this module. The
/// telemetry module's `init_telemetry` therefore needs a wrapper here so
/// `native.initTelemetry(...)` is callable from Dart.
///
/// # Args
/// - `dsn`: Sentry DSN. Empty string disables Sentry; the on-disk panic
///   fallback still runs.
/// - `release`: e.g. `"svid@1.3.7+12"` — passed from Dart so the release
///   tag tracks `AppConstants.appVersion` + brand, NOT the Rust crate's
///   `0.1.0` `CARGO_PKG_VERSION`.
/// - `panic_dir`: brand-resolved absolute path for panic JSON files.
pub fn init_telemetry(dsn: Option<String>, release: String, panic_dir: String) {
    crate::telemetry::init_telemetry(dsn, release, panic_dir);
}

/// Download a file from URL to path
pub async fn download_file(url: String, path: String) -> anyhow::Result<String> {
    crate::telemetry::instrumented_async("rust.download.file", async {
        let mut engine = DownloadEngine::new();
        engine.download(&url, &path).await?;
        Ok(format!("Downloaded to: {}", path))
    })
    .await
}

/// Get directory size recursively
pub fn get_directory_size(path: String) -> anyhow::Result<u64> {
    crate::telemetry::instrumented_call("rust.fs.get_directory_size", || {
        let size = scan_directory(&path)?;
        Ok(size)
    })
}

// ============================================================================
// yt-dlp API Functions
// ============================================================================

/// Format/quality option from yt-dlp
pub struct YtDlpFormatDto {
    pub format_id: String,
    pub ext: String,
    pub resolution: Option<String>,
    pub height: Option<u32>,
    pub width: Option<u32>,
    pub filesize: Option<u64>,
    pub vcodec: Option<String>,
    pub acodec: Option<String>,
    pub fps: Option<f64>,
    pub tbr: Option<f64>,
    pub format_note: Option<String>,
}

impl From<YtDlpFormat> for YtDlpFormatDto {
    fn from(f: YtDlpFormat) -> Self {
        Self {
            format_id: f.format_id,
            ext: f.ext,
            resolution: f.resolution,
            height: f.height,
            width: f.width,
            filesize: f.filesize,
            vcodec: f.vcodec,
            acodec: f.acodec,
            fps: f.fps,
            tbr: f.tbr,
            format_note: f.format_note,
        }
    }
}

/// Subtitle track information
pub struct SubtitleInfoDto {
    pub lang: String,
    pub lang_name: Option<String>,
    pub ext: String,
    pub url: Option<String>,
}

impl From<crate::ytdlp::parser::SubtitleInfo> for SubtitleInfoDto {
    fn from(sub: crate::ytdlp::parser::SubtitleInfo) -> Self {
        Self {
            lang: sub.lang,
            lang_name: sub.lang_name,
            ext: sub.ext,
            url: sub.url,
        }
    }
}

/// Chapter information
pub struct ChapterInfoDto {
    pub title: String,
    pub start_time: f64,
    pub end_time: f64,
}

impl From<crate::ytdlp::parser::ChapterInfo> for ChapterInfoDto {
    fn from(ch: crate::ytdlp::parser::ChapterInfo) -> Self {
        Self {
            title: ch.title,
            start_time: ch.start_time,
            end_time: ch.end_time,
        }
    }
}

/// Video information from yt-dlp
pub struct YtDlpVideoInfoDto {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub uploader: Option<String>,
    pub uploader_id: Option<String>,
    pub duration: Option<u64>,
    pub view_count: Option<u64>,
    pub like_count: Option<u64>,
    pub upload_date: Option<String>,
    pub thumbnail: Option<String>,
    pub webpage_url: Option<String>,
    pub extractor: Option<String>,
    pub formats: Vec<YtDlpFormatDto>,
    // P0/P1 fields
    pub subtitles: Vec<SubtitleInfoDto>,
    pub automatic_captions: Vec<SubtitleInfoDto>,
    pub chapters: Vec<ChapterInfoDto>,
    pub is_live: bool,
    pub live_status: Option<String>,
}

impl From<YtDlpVideoInfo> for YtDlpVideoInfoDto {
    fn from(info: YtDlpVideoInfo) -> Self {
        Self {
            id: info.id,
            title: info.title,
            description: info.description,
            uploader: info.uploader,
            uploader_id: info.uploader_id,
            duration: info.duration,
            view_count: info.view_count,
            like_count: info.like_count,
            upload_date: info.upload_date,
            thumbnail: info.thumbnail,
            webpage_url: info.webpage_url,
            extractor: info.extractor,
            formats: info.formats.into_iter().map(|f| f.into()).collect(),
            // P0/P1 fields
            subtitles: info.subtitles.into_iter().map(|s| s.into()).collect(),
            automatic_captions: info.automatic_captions.into_iter().map(|s| s.into()).collect(),
            chapters: info.chapters.into_iter().map(|c| c.into()).collect(),
            is_live: info.is_live,
            live_status: info.live_status,
        }
    }
}

/// Check if yt-dlp is available
pub async fn ytdlp_is_available(binary_path: String) -> bool {
    let config = YtDlpConfig {
        binary_path,
        ..Default::default()
    };
    let executor = YtDlpExecutor::new(config);
    executor.is_available().await
}

/// Get yt-dlp version
pub async fn ytdlp_get_version(binary_path: String) -> anyhow::Result<String> {
    crate::telemetry::instrumented_async("rust.ytdlp.get_version", async {
        let config = YtDlpConfig {
            binary_path,
            ..Default::default()
        };
        let executor = YtDlpExecutor::new(config);
        executor.get_version().await
    })
    .await
}

/// Extract video information without downloading
pub async fn ytdlp_extract_info(
    binary_path: String,
    url: String,
    cookies_file: Option<String>,
    cookies_from_browser: Option<String>,
    proxy_url: Option<String>,
    extractor_client: Option<String>,
    timeout_secs: Option<u64>,
    js_runtime_path: Option<String>,
) -> anyhow::Result<YtDlpVideoInfoDto> {
    crate::telemetry::instrumented_async("rust.ytdlp.extract_info", async {
        let config = YtDlpConfig {
            binary_path,
            cookies_file,
            cookies_from_browser,
            proxy_url,
            extractor_client,
            timeout_seconds: timeout_secs.unwrap_or(30),
            js_runtime_path,
            ..Default::default()
        };
        let mut executor = YtDlpExecutor::new(config);
        let info = executor.extract_info(&url).await?;
        Ok(info.into())
    })
    .await
}

// NOTE: ytdlp_download() removed - downloads use Dart Process.start for real-time progress
// The Rust executor.download() is kept for potential future use but not exposed via FFI

// ============================================================================
// YouTube Search API
// ============================================================================

/// YouTube search result DTO
pub struct YouTubeSearchResultDto {
    pub id: String,
    pub title: String,
    pub channel: Option<String>,
    pub channel_id: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<u64>,
    pub view_count: Option<u64>,
    pub upload_date: Option<String>,
    pub url: String,
    pub description: Option<String>,
}

impl From<YouTubeSearchResult> for YouTubeSearchResultDto {
    fn from(r: YouTubeSearchResult) -> Self {
        Self {
            id: r.id,
            title: r.title,
            channel: r.channel,
            channel_id: r.channel_id,
            thumbnail: r.thumbnail,
            duration: r.duration,
            view_count: r.view_count,
            upload_date: r.upload_date,
            url: r.url,
            description: r.description,
        }
    }
}

/// Search YouTube videos
/// Returns a list of search results with basic metadata
///
/// # Arguments
/// * `binary_path` - Path to yt-dlp binary
/// * `query` - Search query string
/// * `max_results` - Maximum number of results (1-50, default: 20)
/// * `cookies_file` - Optional cookies file for age-restricted content
pub async fn ytdlp_search_youtube(
    binary_path: String,
    query: String,
    max_results: u32,
    cookies_file: Option<String>,
    cookies_from_browser: Option<String>,
    js_runtime_path: Option<String>,
) -> anyhow::Result<Vec<YouTubeSearchResultDto>> {
    crate::telemetry::instrumented_async("rust.ytdlp.search_youtube", async {
        let config = YtDlpConfig {
            binary_path,
            cookies_file,
            cookies_from_browser,
            timeout_seconds: 30,
            js_runtime_path,
            ..Default::default()
        };
        let mut executor = YtDlpExecutor::new(config);
        let results = executor.search_youtube(&query, max_results).await?;
        Ok(results.into_iter().map(|r| r.into()).collect())
    })
    .await
}

// ============================================================================
// Playlist API
// ============================================================================

/// Playlist info DTO
pub struct PlaylistInfoDto {
    pub id: String,
    pub title: String,
    pub uploader: Option<String>,
    pub uploader_id: Option<String>,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub video_count: Option<u32>,
    pub webpage_url: String,
}

impl From<PlaylistInfo> for PlaylistInfoDto {
    fn from(p: PlaylistInfo) -> Self {
        Self {
            id: p.id,
            title: p.title,
            uploader: p.uploader,
            uploader_id: p.uploader_id,
            thumbnail: p.thumbnail,
            description: p.description,
            video_count: p.video_count,
            webpage_url: p.webpage_url,
        }
    }
}

/// Playlist video DTO
pub struct PlaylistVideoDto {
    pub id: String,
    pub title: String,
    pub url: String,
    pub thumbnail: Option<String>,
    pub duration: Option<u64>,
    pub channel: Option<String>,
    pub channel_id: Option<String>,
    pub view_count: Option<u64>,
    pub upload_date: Option<String>,
}

impl From<PlaylistVideo> for PlaylistVideoDto {
    fn from(v: PlaylistVideo) -> Self {
        Self {
            id: v.id,
            title: v.title,
            url: v.url,
            thumbnail: v.thumbnail,
            duration: v.duration,
            channel: v.channel,
            channel_id: v.channel_id,
            view_count: v.view_count,
            upload_date: v.upload_date,
        }
    }
}

/// Get YouTube playlist information with pagination support
/// Returns playlist metadata and list of videos for the specified range
///
/// # Arguments
/// * `binary_path` - Path to yt-dlp binary
/// * `url` - Playlist URL (e.g., https://www.youtube.com/playlist?list=...)
/// * `start_index` - Start index (1-based, 0 = from beginning)
/// * `end_index` - End index (1-based, 0 = no limit)
/// * `cookies_file` - Optional cookies file for private/age-restricted playlists
pub async fn ytdlp_get_playlist_info(
    binary_path: String,
    url: String,
    start_index: u32,
    end_index: u32,
    cookies_file: Option<String>,
    cookies_from_browser: Option<String>,
    js_runtime_path: Option<String>,
) -> anyhow::Result<(PlaylistInfoDto, Vec<PlaylistVideoDto>)> {
    crate::telemetry::instrumented_async("rust.ytdlp.get_playlist_info", async {
        let config = YtDlpConfig {
            binary_path,
            cookies_file,
            cookies_from_browser,
            timeout_seconds: 60,
            js_runtime_path,
            ..Default::default()
        };
        let mut executor = YtDlpExecutor::new(config);
        let (playlist, videos) = executor.get_playlist_info(&url, start_index, end_index).await?;
        Ok((
            playlist.into(),
            videos.into_iter().map(|v| v.into()).collect(),
        ))
    })
    .await
}

// ============================================================================
// YouTube Channel API
// ============================================================================

/// Channel info DTO
pub struct ChannelInfoDto {
    pub id: String,
    pub title: String,
    pub uploader: Option<String>,
    pub uploader_id: Option<String>,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub subscriber_count: Option<u64>,
    pub video_count: Option<u32>,
    pub webpage_url: String,
}

impl From<ChannelInfo> for ChannelInfoDto {
    fn from(c: ChannelInfo) -> Self {
        Self {
            id: c.id,
            title: c.title,
            uploader: c.uploader,
            uploader_id: c.uploader_id,
            thumbnail: c.thumbnail,
            description: c.description,
            subscriber_count: c.subscriber_count,
            video_count: c.video_count,
            webpage_url: c.webpage_url,
        }
    }
}

/// Get YouTube channel information with pagination support
/// Returns channel metadata and list of videos for the specified range
/// Works with @username, /c/channel, /channel/ID URLs
///
/// # Arguments
/// * `binary_path` - Path to yt-dlp binary
/// * `url` - Channel URL (e.g., https://www.youtube.com/@username or /channel/UCID)
/// * `start_index` - Start index (1-based, 0 = from beginning)
/// * `end_index` - End index (1-based, 0 = no limit)
/// * `cookies_file` - Optional cookies file for age-restricted channels
pub async fn ytdlp_get_channel_info(
    binary_path: String,
    url: String,
    start_index: u32,
    end_index: u32,
    cookies_file: Option<String>,
    cookies_from_browser: Option<String>,
    js_runtime_path: Option<String>,
) -> anyhow::Result<(ChannelInfoDto, Vec<PlaylistVideoDto>)> {
    crate::telemetry::instrumented_async("rust.ytdlp.get_channel_info", async {
        let config = YtDlpConfig {
            binary_path,
            cookies_file,
            cookies_from_browser,
            timeout_seconds: 60,
            js_runtime_path,
            ..Default::default()
        };
        let mut executor = YtDlpExecutor::new(config);
        let (channel, videos) = executor.get_channel_info(&url, start_index, end_index).await?;
        Ok((
            channel.into(),
            videos.into_iter().map(|v| v.into()).collect(),
        ))
    })
    .await
}

/// Get YouTube channel metadata ONLY (accurate avatar, banner, description)
/// This is a separate call optimized for getting channel page data without videos
/// Use this when you need accurate channel thumbnails/avatars for subscriptions
///
/// # Arguments
/// * `binary_path` - Path to yt-dlp binary
/// * `url` - Channel URL (e.g., https://www.youtube.com/@username or /channel/UCID)
/// * `cookies_file` - Optional cookies file for age-restricted channels
pub async fn ytdlp_get_channel_metadata(
    binary_path: String,
    url: String,
    cookies_file: Option<String>,
    cookies_from_browser: Option<String>,
    js_runtime_path: Option<String>,
) -> anyhow::Result<ChannelInfoDto> {
    crate::telemetry::instrumented_async("rust.ytdlp.get_channel_metadata", async {
        let config = YtDlpConfig {
            binary_path,
            cookies_file,
            cookies_from_browser,
            timeout_seconds: 20,
            js_runtime_path,
            ..Default::default()
        };
        let mut executor = YtDlpExecutor::new(config);
        let channel = executor.get_channel_metadata(&url).await?;
        Ok(channel.into())
    })
    .await
}

/// Parse yt-dlp progress line (helper for Dart-side parsing)
pub fn ytdlp_parse_progress(line: String) -> Option<YtDlpProgressDto> {
    crate::ytdlp::parser::parse_progress_line(&line).map(|p| YtDlpProgressDto {
        percent: p.percent,
        downloaded_bytes: p.downloaded_bytes,
        total_bytes: p.total_bytes,
        speed: p.speed,
        eta_seconds: p.eta_seconds,
        status: match p.status {
            YtDlpStatus::Downloading => "downloading".to_string(),
            YtDlpStatus::PostProcessing => "postprocessing".to_string(),
            YtDlpStatus::Finished => "finished".to_string(),
            YtDlpStatus::Error => "error".to_string(),
        },
    })
}

/// Progress DTO for Dart
pub struct YtDlpProgressDto {
    pub percent: f64,
    pub downloaded_bytes: Option<u64>,
    pub total_bytes: Option<u64>,
    pub speed: Option<f64>,
    pub eta_seconds: Option<u64>,
    pub status: String,
}

// ============================================================================
// Download Manager API
// ============================================================================

/// Initialize download manager (call once at app start)
pub async fn download_manager_init(max_concurrent: u32) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.manager_init", async {
        crate::context::init_context(max_concurrent as usize).await
    })
    .await
}

/// Start a new download with optional resume offset, speed limit, segment count, user agent, and proxy
///
/// # Arguments
/// * `id` - UUID string for download tracking
/// * `url` - Direct HTTP URL to download from
/// * `output_path` - File path to save download
/// * `resume_offset` - Optional byte offset to resume from (0 = start new download)
/// * `max_speed_bytes` - Optional speed limit in bytes/second (0 or None = unlimited)
/// * `num_segments` - Optional number of parallel segments (None/1 = single-stream, 2-16 = segmented)
/// * `user_agent` - Optional User-Agent string for HTTP requests (None = default Chrome UA)
/// * `proxy_url` - Optional proxy URL (e.g. "http://host:port", "socks5://host:port"; None = no proxy)
pub async fn download_start(
    id: String,
    url: String,
    output_path: String,
    resume_offset: Option<u64>,
    max_speed_bytes: Option<u64>,
    num_segments: Option<u32>,
    user_agent: Option<String>,
    proxy_url: Option<String>,
) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.start", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        manager.start_download(
            uuid,
            url,
            output_path,
            resume_offset.unwrap_or(0),
            max_speed_bytes.unwrap_or(0),
            num_segments.unwrap_or(1),
            user_agent,
            proxy_url,
        ).await
    })
    .await
}

/// Start a download with custom HTTP headers and cookies (IDM mode).
///
/// This is the advanced API used by the browser media interceptor to download
/// URLs directly with the browser's authentication context.
///
/// # Arguments
/// * `id` - UUID string for download tracking
/// * `url` - Direct HTTP URL to download from
/// * `output_path` - File path to save download
/// * `resume_offset` - Optional byte offset to resume from
/// * `max_speed_bytes` - Optional speed limit in bytes/second
/// * `num_segments` - Optional number of parallel segments (1 = single-stream, 2-16 = segmented)
/// * `user_agent` - Optional User-Agent string
/// * `proxy_url` - Optional proxy URL
/// * `headers_json` - Optional JSON string of custom HTTP headers: `{"Cookie":"…","Referer":"…"}`
/// * `cookies_string` - Optional raw cookie string: `"key1=val1; key2=val2"`
pub async fn download_start_with_headers(
    id: String,
    url: String,
    output_path: String,
    resume_offset: Option<u64>,
    max_speed_bytes: Option<u64>,
    num_segments: Option<u32>,
    user_agent: Option<String>,
    proxy_url: Option<String>,
    headers_json: Option<String>,
    cookies_string: Option<String>,
) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.start_with_headers", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;

        // Build DownloadConfig with custom headers
        let mut custom_headers = if let Some(ref json) = headers_json {
            DownloadConfig::parse_headers_json(json)
        } else {
            std::collections::HashMap::new()
        };

        // Merge cookies_string into Cookie header
        if let Some(ref cookies) = cookies_string {
            if !cookies.is_empty() {
                custom_headers.insert("Cookie".to_string(), cookies.clone());
            }
        }

        let config = DownloadConfig {
            user_agent,
            proxy_url,
            custom_headers,
        };

        let manager = ctx.download_manager.lock().await;
        manager.start_download_with_config(
            uuid,
            url,
            output_path,
            resume_offset.unwrap_or(0),
            max_speed_bytes.unwrap_or(0),
            num_segments.unwrap_or(1),
            config,
        ).await
    })
    .await
}

/// Pause a download
pub async fn download_pause(id: String) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.pause", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        manager.pause_download(uuid).await
    })
    .await
}

/// Resume a download
pub async fn download_resume(id: String) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.resume", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        manager.resume_download(uuid).await
    })
    .await
}

/// Cancel a download
pub async fn download_cancel(id: String) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.cancel", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        manager.cancel_download(uuid).await
    })
    .await
}

/// Get download progress
pub async fn download_get_progress(id: String) -> anyhow::Result<DownloadProgressDto> {
    crate::telemetry::instrumented_async("rust.download.get_progress", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        let progress = manager.get_progress(uuid).await?;

        Ok(DownloadProgressDto {
            id: progress.id.to_string(),
            downloaded_bytes: progress.downloaded_bytes,
            total_bytes: progress.total_bytes,
            status: progress.status,
        })
    })
    .await
}

/// Download progress DTO
pub struct DownloadProgressDto {
    pub id: String,
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub status: String,
}

/// Remove a completed/failed/cancelled download from Rust memory.
/// Call this after a download reaches a terminal state to prevent memory leaks.
pub async fn download_cleanup(id: String) -> anyhow::Result<()> {
    crate::telemetry::instrumented_async("rust.download.cleanup", async {
        let uuid = uuid::Uuid::parse_str(&id)?;
        let ctx = crate::context::get_context()?;
        let manager = ctx.download_manager.lock().await;
        manager.cleanup_download(uuid).await
    })
    .await
}

// NOTE: Real-time streaming removed due to flutter_rust_bridge Stream limitations
// The current polling approach via download_get_progress() works well for production
// Progress is updated every 100ms internally and accessible via get_progress() calls
//
// If streaming is needed in the future, consider:
// 1. Using flutter_rust_bridge StreamSink pattern
// 2. Implementing a Dart-side timer that polls get_progress() every 200-500ms
// 3. Using platform channels for true push notifications
