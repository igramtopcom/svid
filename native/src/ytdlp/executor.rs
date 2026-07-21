/// yt-dlp subprocess executor
/// Handles running yt-dlp binary, capturing output, and managing process lifecycle

use crate::ytdlp::parser::{parse_error, parse_playlist_info, parse_channel_info, parse_channel_metadata, parse_progress_line, parse_video_info, parse_search_results, ChannelInfo, PlaylistInfo, PlaylistVideo, YtDlpError, YtDlpProgress, YtDlpVideoInfo, YtDlpStatus, YouTubeSearchResult};
use anyhow::{Context, Result};
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
#[cfg(target_os = "windows")]
use std::sync::OnceLock;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
#[cfg(target_os = "windows")]
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

/// Windows: hide console window when spawning yt-dlp subprocesses.
/// Without this, every yt-dlp call pops up a visible cmd window.
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

/// Apply Windows-specific creation flags to hide console window.
/// No-op on non-Windows platforms.
#[cfg(target_os = "windows")]
fn hide_console(cmd: &mut Command) {
    cmd.creation_flags(CREATE_NO_WINDOW);
}
#[cfg(not(target_os = "windows"))]
fn hide_console(_cmd: &mut Command) {}

/// Windows real-time AV/Defender can spike CPU/RAM when many yt-dlp.exe
/// processes launch at once. Keep native direct-spawn faster than cmd.exe
/// while preserving bounded pressure on low-end Windows machines.
#[cfg(target_os = "windows")]
static YTDLP_PROCESS_SEMAPHORE: OnceLock<Arc<Semaphore>> = OnceLock::new();

#[cfg(target_os = "windows")]
type YtDlpProcessSlot = OwnedSemaphorePermit;

#[cfg(not(target_os = "windows"))]
struct YtDlpProcessSlot;

#[cfg(target_os = "windows")]
async fn acquire_ytdlp_process_slot() -> YtDlpProcessSlot {
    YTDLP_PROCESS_SEMAPHORE
        .get_or_init(|| Arc::new(Semaphore::new(3)))
        .clone()
        .acquire_owned()
        .await
        .expect("yt-dlp process semaphore closed")
}

#[cfg(not(target_os = "windows"))]
async fn acquire_ytdlp_process_slot() -> YtDlpProcessSlot {
    YtDlpProcessSlot
}

/// Force Python (yt-dlp) to use UTF-8 for all I/O.
/// On Windows, Python defaults to the system codepage (cp1252/Windows-1252),
/// which corrupts non-ASCII characters in stdout/stderr output.
/// PYTHONUTF8 and PYTHONIOENCODING override this to use UTF-8 consistently.
fn configure_python_env(cmd: &mut Command) {
    cmd.env("PYTHONUTF8", "1");
    cmd.env("PYTHONIOENCODING", "utf-8");
}

/// Result type for yt-dlp operations
#[derive(Debug, Clone)]
pub enum YtDlpResult {
    Success { output_path: String },
    Error { error: YtDlpError, message: String },
    Cancelled,
}

/// Configuration for yt-dlp execution
#[derive(Debug, Clone)]
pub struct YtDlpConfig {
    pub binary_path: String,
    pub output_template: String,
    pub format: Option<String>,
    pub cookies_file: Option<String>,
    pub extract_audio: bool,
    pub audio_format: Option<String>,
    pub timeout_seconds: u64,

    // === P0 Features: Subtitles ===
    pub subtitles_enabled: bool,
    pub subtitles_langs: Vec<String>,    // e.g., ["en", "vi", "auto"]
    pub subtitles_format: String,         // "srt", "vtt", "ass"
    pub embed_subtitles: bool,

    // === P0 Features: Thumbnails ===
    pub write_thumbnail: bool,
    pub embed_thumbnail: bool,

    // === P0 Features: Metadata ===
    pub embed_metadata: bool,
    pub embed_chapters: bool,

    // === P0 Features: SponsorBlock ===
    pub sponsorblock_enabled: bool,
    pub sponsorblock_action: String,      // "skip", "remove", "chapter"
    pub sponsorblock_categories: Vec<String>, // ["sponsor", "intro", "outro", ...]

    // === P1 Features: Chapters ===
    pub split_chapters: bool,             // Split video by chapters

    // === P1 Features: Live Stream ===
    pub live_from_start: bool,            // Download live from beginning

    // === User-Agent rotation ===
    pub user_agent: Option<String>,       // Custom UA string (None = default Chrome UA)

    // === Browser cookie import ===
    pub cookies_from_browser: Option<String>, // Browser name for --cookies-from-browser (e.g., "chrome", "firefox")

    // === Proxy ===
    pub proxy_url: Option<String>,        // Proxy URL (e.g., "http://host:port") — passed as --proxy

    // === Extractor Client (YouTube) ===
    /// Override the YouTube player client (e.g., "android", "android_creator", "tv_embedded").
    /// None = use yt-dlp's default (ios,web already baked into extract_info).
    pub extractor_client: Option<String>,

    // === External JS Runtime (Deno) ===
    /// Absolute path to the app-managed Deno binary. Forwarded as
    /// `--js-runtimes deno:<path>`. yt-dlp 2025.11.12+ requires an
    /// external JS runtime for full YouTube support (n-challenge / nsig
    /// signature solving). Without this, logged-in YouTube extraction
    /// returns only storyboard formats — see
    /// `feedback_diff_verbose_output_before_speculate.md`. None = skip
    /// the flag (non-YouTube extractors keep working; YouTube degrades
    /// to storyboards-only with `formatNotAvailable` error reaching UI).
    pub js_runtime_path: Option<String>,
}

impl Default for YtDlpConfig {
    fn default() -> Self {
        Self {
            binary_path: "yt-dlp".to_string(),
            output_template: "%(title)s.%(ext)s".to_string(),
            format: None,
            cookies_file: None,
            extract_audio: false,
            audio_format: None,
            timeout_seconds: 300, // 5 minutes default

            // P0: Subtitles defaults
            subtitles_enabled: false,
            subtitles_langs: vec!["en".to_string()],
            subtitles_format: "srt".to_string(),
            embed_subtitles: false,

            // P0: Thumbnails defaults
            write_thumbnail: false,
            embed_thumbnail: false,

            // P0: Metadata defaults
            embed_metadata: false,
            embed_chapters: false,

            // P0: SponsorBlock defaults
            sponsorblock_enabled: false,
            sponsorblock_action: "skip".to_string(),
            sponsorblock_categories: vec!["sponsor".to_string()],

            // P1: Chapters defaults
            split_chapters: false,

            // P1: Live stream defaults
            live_from_start: false,

            // User-Agent rotation
            user_agent: None,

            // Browser cookie import
            cookies_from_browser: None,

            // Proxy
            proxy_url: None,

            // Extractor client
            extractor_client: None,

            // External JS runtime (Deno) — None = skip --js-runtimes flag
            js_runtime_path: None,
        }
    }
}

/// yt-dlp subprocess executor
pub struct YtDlpExecutor {
    config: YtDlpConfig,
    is_cancelled: Arc<AtomicBool>,
    child: Option<Child>,
}

impl YtDlpExecutor {
    pub fn new(config: YtDlpConfig) -> Self {
        Self {
            config,
            is_cancelled: Arc::new(AtomicBool::new(false)),
            child: None,
        }
    }

    /// Cancel the current operation
    pub fn cancel(&self) {
        self.is_cancelled.store(true, Ordering::SeqCst);
    }

    /// Check if operation is cancelled
    pub fn is_cancelled(&self) -> bool {
        self.is_cancelled.load(Ordering::SeqCst)
    }

    /// Reset cancelled state
    pub fn reset(&self) {
        self.is_cancelled.store(false, Ordering::SeqCst);
    }

    /// Extract video information without downloading
    pub async fn extract_info(&mut self, url: &str) -> Result<YtDlpVideoInfo> {
        self.reset();

        let start_time = std::time::Instant::now();
        let has_cookies =
            self.config.cookies_file.is_some() || self.config.cookies_from_browser.is_some();
        eprintln!(
            "[yt-dlp extract_info] url={}, cookies={}, timeout={}s",
            url, has_cookies, self.config.timeout_seconds
        );

        // Build youtube extractor-args: always skip heavy manifests; optionally override client.
        let extractor_args = match &self.config.extractor_client {
            Some(client) if !client.is_empty() => {
                format!("youtube:skip=hls,dash,translated_subs;player_client={}", client)
            }
            _ => "youtube:skip=hls,dash,translated_subs".to_string(),
        };

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--dump-json",           // Output JSON
            "--no-download",         // Don't download
            "--no-warnings",         // Skip warnings
            "--no-playlist",         // CRITICAL: Only single video, not entire playlist!
            "--no-check-formats",    // Skip format URL verification (metadata only, saves ~0.5-1s)
            "--socket-timeout", "15", // Network timeout 15s
            "--extractor-retries", "2", // Max 2 retries
            "--retry-sleep", "3",    // Sleep 3s between extractor retries (avoids rate-limit burst)
            "--no-check-certificates", // Skip SSL verification (faster)
            // Skip HLS/DASH manifests + translated subs; optionally override player_client.
            "--extractor-args", &extractor_args,
            url,
        ]);

        // Add Deno JS runtime — required by yt-dlp 2025.11.12+ for full
        // YouTube extraction (n-challenge / nsig signature solving).
        // Without it logged-in YouTube returns only storyboard formats.
        // Mirrors the Dart Process.run path injection in
        // `ytdlp_datasource.dart::extractInfo`.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        // Add cookies: --cookies-from-browser takes priority over --cookies file
        self.add_cookie_args(&mut cmd);
        if self.config.cookies_from_browser.is_some() {
            eprintln!("[yt-dlp extract_info] Using browser cookies: {}", self.config.cookies_from_browser.as_ref().unwrap());
        } else if self.config.cookies_file.is_some() {
            eprintln!("[yt-dlp extract_info] Using cookies: {}", self.config.cookies_file.as_ref().unwrap());
        }

        // Add proxy if configured
        if let Some(ref proxy) = self.config.proxy_url {
            if !proxy.is_empty() {
                cmd.args(["--proxy", proxy]);
                eprintln!("[yt-dlp extract_info] Using proxy: {}", proxy);
            }
        }

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let output = tokio::time::timeout(
            std::time::Duration::from_secs(self.config.timeout_seconds),
            async {
                let _process_slot = acquire_ytdlp_process_slot().await;
                cmd.output().await
            },
        )
        .await
        .context("yt-dlp timeout while extracting info")?
        .context("Failed to execute yt-dlp")?;

        let elapsed = start_time.elapsed();

        if self.is_cancelled() {
            eprintln!("[yt-dlp extract_info] Cancelled after {:.1}s", elapsed.as_secs_f64());
            anyhow::bail!("Operation cancelled");
        }

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let error = parse_error(&stderr);
            eprintln!(
                "[yt-dlp extract_info] FAILED after {:.1}s | error={:?} | exit={} | stderr={}",
                elapsed.as_secs_f64(),
                error,
                output.status.code().unwrap_or(-1),
                stderr.chars().take(500).collect::<String>()
            );
            anyhow::bail!("yt-dlp error: {:?} - {}", error, stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        eprintln!(
            "[yt-dlp extract_info] SUCCESS in {:.1}s | stdout_bytes={}",
            elapsed.as_secs_f64(),
            stdout.len()
        );

        parse_video_info(&stdout).context("Failed to parse video info")
    }

    /// Search YouTube videos
    /// Returns a list of search results with basic metadata (no formats)
    ///
    /// # Arguments
    /// * `query` - Search query string
    /// * `max_results` - Maximum number of results to return (default: 20, max: 50)
    pub async fn search_youtube(&mut self, query: &str, max_results: u32) -> Result<Vec<YouTubeSearchResult>> {
        self.reset();

        // Clamp results between 1 and 50
        let limit = max_results.clamp(1, 50);

        // Build ytsearch query: ytsearchN:query
        let search_query = format!("ytsearch{}:{}", limit, query);

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--dump-json",              // Output JSON
            "--no-download",            // Don't download
            "--no-warnings",            // Skip warnings
            "--flat-playlist",          // Get basic info only (faster)
            "--ignore-errors",          // Skip unavailable videos
            "--socket-timeout", "15",   // Network timeout 15s
            "--extractor-retries", "2", // Max 2 retries
            "--no-check-certificates",  // Skip SSL verification (faster)
            &search_query,
        ]);

        // Deno JS runtime — see extract_info above for full rationale.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        // Add cookies if available (for age-restricted results)
        self.add_cookie_args(&mut cmd);

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        // Search timeout: 30 seconds
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(30),
            async {
                let _process_slot = acquire_ytdlp_process_slot().await;
                cmd.output().await
            },
        )
        .await
        .context("YouTube search timeout")?
        .context("Failed to execute yt-dlp search")?;

        if self.is_cancelled() {
            anyhow::bail!("Search cancelled");
        }

        // Check for errors but don't fail completely (some results may still be valid)
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            // If we got some stdout, try to parse it even if there were errors
            if output.stdout.is_empty() {
                let error = parse_error(&stderr);
                anyhow::bail!("YouTube search failed: {:?} - {}", error, stderr);
            }
            // Log warning but continue with partial results
            eprintln!("Warning: Some search results may be incomplete: {}", stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let results = parse_search_results(&stdout);

        Ok(results)
    }

    /// Get YouTube playlist information with pagination support
    /// Uses --flat-playlist for fast metadata extraction without downloading formats
    ///
    /// # Arguments
    /// * `url` - Playlist URL (e.g., https://www.youtube.com/playlist?list=...)
    /// * `start_index` - Start index (1-based, 0 = from beginning)
    /// * `end_index` - End index (1-based, 0 = no limit)
    pub async fn get_playlist_info(&mut self, url: &str, start_index: u32, end_index: u32) -> Result<(PlaylistInfo, Vec<PlaylistVideo>)> {
        self.reset();

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--dump-json",              // Output JSON
            "--no-download",            // Don't download
            "--no-warnings",            // Skip warnings
            "--flat-playlist",          // Get basic info only (no format extraction)
            "--ignore-errors",          // Skip unavailable videos
            "--socket-timeout", "15",   // Network timeout 15s
            "--extractor-retries", "2", // Max 2 retries
            "--no-check-certificates",  // Skip SSL verification (faster)
        ]);

        // Deno JS runtime — see extract_info above for full rationale.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        // Add pagination parameters
        if start_index > 0 {
            cmd.args(["--playlist-start", &start_index.to_string()]);
        }
        if end_index > 0 {
            cmd.args(["--playlist-end", &end_index.to_string()]);
        }

        cmd.arg(url);

        // Add cookies if available (for private/age-restricted playlists)
        self.add_cookie_args(&mut cmd);

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        // Playlist timeout: 60 seconds (paginated requests are faster)
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(60),
            async {
                let _process_slot = acquire_ytdlp_process_slot().await;
                cmd.output().await
            },
        )
        .await
        .context("Playlist extraction timeout")?
        .context("Failed to execute yt-dlp")?;

        if self.is_cancelled() {
            anyhow::bail!("Operation cancelled");
        }

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.stdout.is_empty() {
                let error = parse_error(&stderr);
                anyhow::bail!("Playlist extraction failed: {:?} - {}", error, stderr);
            }
            // Keep parity with the Dart path: --ignore-errors can still emit
            // usable partial JSON when individual playlist entries fail.
            eprintln!("Warning: Some playlist entries may be incomplete: {}", stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        parse_playlist_info(&stdout).context("Failed to parse playlist info")
    }

    /// Get YouTube channel information with pagination support
    /// Uses --flat-playlist for fast metadata extraction without downloading formats
    /// Works with channel URLs (@username, /c/channel, /channel/ID)
    ///
    /// # Arguments
    /// * `url` - Channel URL (e.g., https://www.youtube.com/@username or /channel/UCID)
    /// * `start_index` - Start index (1-based, 0 = from beginning)
    /// * `end_index` - End index (1-based, 0 = no limit)
    pub async fn get_channel_info(&mut self, url: &str, start_index: u32, end_index: u32) -> Result<(ChannelInfo, Vec<PlaylistVideo>)> {
        self.reset();

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--dump-json",              // Output JSON
            "--no-download",            // Don't download
            "--no-warnings",            // Skip warnings
            "--flat-playlist",          // Get basic info only (no format extraction)
            "--ignore-errors",          // Skip unavailable videos
            "--socket-timeout", "15",   // Network timeout 15s
            "--extractor-retries", "2", // Max 2 retries
            "--no-check-certificates",  // Skip SSL verification (faster)
        ]);

        // Deno JS runtime — see extract_info above for full rationale.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        // Add pagination parameters
        if start_index > 0 {
            cmd.args(["--playlist-start", &start_index.to_string()]);
        }
        if end_index > 0 {
            cmd.args(["--playlist-end", &end_index.to_string()]);
        }

        cmd.arg(url);

        // Add cookies if available (for age-restricted channels)
        self.add_cookie_args(&mut cmd);

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        // Channel timeout: 60 seconds (same as playlists)
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(60),
            async {
                let _process_slot = acquire_ytdlp_process_slot().await;
                cmd.output().await
            },
        )
        .await
        .context("Channel extraction timeout")?
        .context("Failed to execute yt-dlp")?;

        if self.is_cancelled() {
            anyhow::bail!("Operation cancelled");
        }

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.stdout.is_empty() {
                let error = parse_error(&stderr);
                anyhow::bail!("Channel extraction failed: {:?} - {}", error, stderr);
            }
            // Keep parity with the Dart path: --ignore-errors can still emit
            // usable partial JSON when individual channel entries fail.
            eprintln!("Warning: Some channel entries may be incomplete: {}", stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        parse_channel_info(&stdout, url).context("Failed to parse channel info")
    }

    /// Get YouTube channel metadata ONLY (avatar, banner, description)
    /// Uses single entry extraction (no --flat-playlist) to get full channel page data
    /// This is slower but provides accurate channel thumbnail/avatar
    ///
    /// # Arguments
    /// * `url` - Channel URL (e.g., https://www.youtube.com/@username)
    pub async fn get_channel_metadata(&mut self, url: &str) -> Result<ChannelInfo> {
        self.reset();

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--dump-json",              // Output JSON
            "--no-download",            // Don't download
            "--no-warnings",            // Skip warnings
            "--playlist-items", "0",    // Get channel page only, no videos
            "--socket-timeout", "15",   // Network timeout 15s
            "--extractor-retries", "2", // Max 2 retries
            "--no-check-certificates",  // Skip SSL verification (faster)
        ]);

        // Deno JS runtime — see extract_info above for full rationale.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        cmd.arg(url);

        // Add cookies if available (for age-restricted channels)
        self.add_cookie_args(&mut cmd);

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        // Channel metadata timeout: 20 seconds (faster than full channel fetch)
        let output = tokio::time::timeout(
            std::time::Duration::from_secs(20),
            async {
                let _process_slot = acquire_ytdlp_process_slot().await;
                cmd.output().await
            },
        )
        .await
        .context("Channel metadata extraction timeout")?
        .context("Failed to execute yt-dlp")?;

        if self.is_cancelled() {
            anyhow::bail!("Operation cancelled");
        }

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.stdout.is_empty() {
                anyhow::bail!("yt-dlp failed to extract channel metadata: {}", stderr);
            }
            // Preserve old Dart behavior: parse JSON when yt-dlp returned data
            // but also emitted a recoverable warning/error on stderr.
            eprintln!("Warning: Channel metadata stderr: {}", stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        parse_channel_metadata(&stdout).context("Failed to parse channel metadata")
    }

    /// Download video with progress reporting
    pub async fn download(
        &mut self,
        url: &str,
        output_dir: &str,
        progress_tx: mpsc::Sender<YtDlpProgress>,
    ) -> Result<YtDlpResult> {
        self.reset();

        let output_path = Path::new(output_dir).join(&self.config.output_template);
        let output_str = output_path.to_string_lossy().to_string();

        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        cmd.args([
            "--newline",           // Progress on each line
            "--progress",          // Show progress
            "--no-warnings",       // Skip warnings
            "--no-playlist",       // Single video only (avoid accidental playlist downloads)
            "--no-check-certificates", // Skip SSL verification
            "--socket-timeout", "30", // Network timeout 30s
            "--retries", "3",      // Retry failed downloads up to 3 times
            "--fragment-retries", "3", // Retry failed fragments
            "--http-chunk-size", "10M", // Chunk size to avoid throttling
            // NO extractor-args = ALL formats available (same as extraction)
            // If 403 error occurs, user should provide cookies for authentication
            "--merge-output-format", "mp4", // Merge DASH video+audio into mp4
            "--user-agent", self.config.user_agent.as_deref().unwrap_or(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            ),
            "--force-ipv4",        // Avoid IPv6 issues
            "-o", &output_str,
            url,
        ]);

        // Add format selection
        if let Some(ref format) = self.config.format {
            cmd.args(["-f", format]);
            // Prioritize resolution when selecting formats (prevents 360p fallback)
            cmd.args(["-S", "res,ext:mp4:m4a"]);
        }

        // Add cookies if available
        self.add_cookie_args(&mut cmd);

        // External JS runtime (Deno) — required by yt-dlp 2025.11.12+ to
        // solve YouTube nsig + n-challenge. Currently this download()
        // path is dead code: the Dart side runs its own subprocess for
        // download with real-time progress (see api.rs comment "ytdlp_download()
        // removed - downloads use Dart Process.start"). We still wire
        // the arg here so any future re-enable does not silently fall
        // back to the deprecated built-in jsinterp and regress YouTube.
        if let Some(ref deno_path) = self.config.js_runtime_path {
            if !deno_path.is_empty() {
                cmd.args(["--js-runtimes", &format!("deno:{}", deno_path)]);
            }
        }

        // Audio extraction
        if self.config.extract_audio {
            cmd.arg("-x");
            if let Some(ref audio_format) = self.config.audio_format {
                cmd.args(["--audio-format", audio_format]);
            }
        }

        // === P0: Subtitles ===
        if self.config.subtitles_enabled {
            cmd.arg("--write-subs");
            cmd.arg("--write-auto-subs"); // Include auto-generated captions
            if !self.config.subtitles_langs.is_empty() {
                cmd.args(["--sub-langs", &self.config.subtitles_langs.join(",")]);
            }
            cmd.args(["--sub-format", &self.config.subtitles_format]);
            if self.config.embed_subtitles {
                cmd.arg("--embed-subs");
            }
        }

        // === P0: Thumbnails ===
        if self.config.write_thumbnail {
            cmd.arg("--write-thumbnail");
            cmd.args(["--convert-thumbnails", "jpg"]); // Convert webp to jpg for compatibility
        }
        if self.config.embed_thumbnail {
            cmd.arg("--embed-thumbnail");
        }

        // === P0: Metadata ===
        if self.config.embed_metadata {
            cmd.arg("--embed-metadata");
        }
        if self.config.embed_chapters {
            cmd.arg("--embed-chapters");
        }

        // === P0: SponsorBlock ===
        if self.config.sponsorblock_enabled && !self.config.sponsorblock_categories.is_empty() {
            let categories = self.config.sponsorblock_categories.join(",");
            match self.config.sponsorblock_action.as_str() {
                "remove" => {
                    // Cut out sponsor segments from video
                    cmd.args(["--sponsorblock-remove", &categories]);
                }
                "chapter" => {
                    // Mark segments as chapters only
                    cmd.args(["--sponsorblock-mark", &categories]);
                }
                _ => {
                    // "skip" - Mark as chapters (default behavior)
                    cmd.args(["--sponsorblock-mark", &categories]);
                }
            }
        }

        // === P1: Split by Chapters ===
        if self.config.split_chapters {
            cmd.arg("--split-chapters");
            // Use chapter title in output filename
            cmd.args(["-o", "chapter:%(title)s - %(section_title)s.%(ext)s"]);
        }

        // === P1: Live Stream Support ===
        if self.config.live_from_start {
            cmd.arg("--live-from-start");
            cmd.args(["--wait-for-video", "30"]); // Wait up to 30s for live to start
        }

        cmd.stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);

        let (_process_slot, child) = tokio::time::timeout(
            std::time::Duration::from_secs(self.config.timeout_seconds),
            async {
                let process_slot = acquire_ytdlp_process_slot().await;
                let child = cmd.spawn().context("Failed to spawn yt-dlp process")?;
                Ok::<_, anyhow::Error>((process_slot, child))
            },
        )
        .await
        .context("yt-dlp timeout while waiting for process slot")??;
        self.child = Some(child);

        // Get stdout for progress parsing
        let stdout = self.child.as_mut().unwrap()
            .stdout
            .take()
            .context("Failed to capture stdout")?;

        let stderr = self.child.as_mut().unwrap()
            .stderr
            .take()
            .context("Failed to capture stderr")?;

        let is_cancelled = self.is_cancelled.clone();
        let mut stderr_lines = BufReader::new(stderr).lines();
        let mut stderr_output = String::new();

        // Spawn stderr reader task
        let stderr_handle = tokio::spawn(async move {
            let mut output = String::new();
            while let Ok(Some(line)) = stderr_lines.next_line().await {
                output.push_str(&line);
                output.push('\n');
            }
            output
        });

        // Read stdout for progress
        let mut stdout_lines = BufReader::new(stdout).lines();
        let mut last_output_file = String::new();

        while let Ok(Some(line)) = stdout_lines.next_line().await {
            if is_cancelled.load(Ordering::SeqCst) {
                // Kill the process
                if let Some(ref mut child) = self.child {
                    let _ = child.kill().await;
                }
                return Ok(YtDlpResult::Cancelled);
            }

            // Parse progress
            if let Some(progress) = parse_progress_line(&line) {
                let _ = progress_tx.send(progress).await;
            }

            // Capture destination file
            if line.contains("[download] Destination:") {
                if let Some(path) = line.strip_prefix("[download] Destination: ") {
                    last_output_file = path.trim().to_string();
                }
            }

            // Check for merger output (final file might differ)
            if line.contains("[Merger]") || line.contains("Merging formats") {
                if let Some(pos) = line.find("into") {
                    let after = &line[pos + 4..];
                    last_output_file = after.trim().trim_matches('"').to_string();
                }
            }
        }

        // Wait for process to complete
        let status = self.child.as_mut().unwrap()
            .wait()
            .await
            .context("Failed to wait for yt-dlp")?;

        // Get stderr output
        stderr_output = stderr_handle.await.unwrap_or_default();

        if !status.success() {
            let error = parse_error(&stderr_output);
            return Ok(YtDlpResult::Error {
                error,
                message: stderr_output,
            });
        }

        // Send final progress
        let _ = progress_tx.send(YtDlpProgress {
            percent: 100.0,
            status: YtDlpStatus::Finished,
            ..Default::default()
        }).await;

        Ok(YtDlpResult::Success {
            output_path: last_output_file,
        })
    }

    /// Get yt-dlp version
    pub async fn get_version(&self) -> Result<String> {
        let mut cmd = Command::new(&self.config.binary_path);
        hide_console(&mut cmd);
        configure_python_env(&mut cmd);
        let output = cmd
            .arg("--version")
            .kill_on_drop(true)
            .output()
            .await
            .context("Failed to get yt-dlp version")?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        } else {
            anyhow::bail!("yt-dlp not found or not working")
        }
    }

    /// Check if yt-dlp binary exists and is executable
    pub async fn is_available(&self) -> bool {
        self.get_version().await.is_ok()
    }

    /// Update configuration
    pub fn set_config(&mut self, config: YtDlpConfig) {
        self.config = config;
    }

    /// Set cookies file path
    pub fn set_cookies(&mut self, path: Option<String>) {
        self.config.cookies_file = path;
    }

    /// Add cookie arguments to a command.
    /// --cookies-from-browser takes priority over --cookies file.
    fn add_cookie_args(&self, cmd: &mut Command) {
        if let Some(ref browser) = self.config.cookies_from_browser {
            cmd.args(["--cookies-from-browser", browser]);
        } else if let Some(ref cookies) = self.config.cookies_file {
            cmd.args(["--cookies", cookies]);
        }
    }

    /// Set output format
    pub fn set_format(&mut self, format: Option<String>) {
        self.config.format = format;
    }
}

impl Drop for YtDlpExecutor {
    fn drop(&mut self) {
        // Kill any running child process immediately and reap it when dropping
        // inside a Tokio runtime. This keeps abandoned Windows process handles
        // from accumulating after cancellation or owner teardown.
        if let Some(mut child) = self.child.take() {
            let _ = child.start_kill();
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let _ = child.wait().await;
                });
            }
        }
        self.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_config_default() {
        let config = YtDlpConfig::default();
        assert_eq!(config.timeout_seconds, 300);
        assert!(!config.extract_audio);
    }

    #[tokio::test]
    async fn test_executor_cancel() {
        let executor = YtDlpExecutor::new(YtDlpConfig::default());
        assert!(!executor.is_cancelled());
        executor.cancel();
        assert!(executor.is_cancelled());
        executor.reset();
        assert!(!executor.is_cancelled());
    }
}
