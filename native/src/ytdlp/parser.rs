/// yt-dlp output parser
/// Parses progress lines and JSON metadata from yt-dlp stdout/stderr

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// Progress information parsed from yt-dlp output
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct YtDlpProgress {
    pub percent: f64,
    pub downloaded_bytes: Option<u64>,
    pub total_bytes: Option<u64>,
    pub speed: Option<f64>,         // bytes per second
    pub eta_seconds: Option<u64>,
    pub status: YtDlpStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum YtDlpStatus {
    Downloading,
    PostProcessing,
    Finished,
    Error,
}

/// YouTube search result (lightweight metadata from --flat-playlist)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct YouTubeSearchResult {
    pub id: String,
    pub title: String,
    pub channel: Option<String>,
    pub channel_id: Option<String>,
    pub thumbnail: Option<String>,
    pub duration: Option<u64>,          // seconds
    pub view_count: Option<u64>,
    pub upload_date: Option<String>,    // YYYYMMDD or relative like "2 days ago"
    pub url: String,                    // Full YouTube URL
    pub description: Option<String>,
}

/// YouTube playlist metadata
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PlaylistInfo {
    pub id: String,
    pub title: String,
    pub uploader: Option<String>,
    pub uploader_id: Option<String>,
    pub thumbnail: Option<String>,
    pub description: Option<String>,
    pub video_count: Option<u32>,
    pub webpage_url: String,
}

/// YouTube channel metadata
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ChannelInfo {
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

/// Video entry in a playlist or channel (lightweight, no format info)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PlaylistVideo {
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

/// Video metadata extracted from yt-dlp
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct YtDlpVideoInfo {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub uploader: Option<String>,
    pub uploader_id: Option<String>,
    pub duration: Option<u64>,          // seconds
    pub view_count: Option<u64>,
    pub like_count: Option<u64>,
    pub upload_date: Option<String>,    // YYYYMMDD format
    pub thumbnail: Option<String>,
    pub webpage_url: Option<String>,
    pub extractor: Option<String>,      // youtube, tiktok, etc.
    pub formats: Vec<YtDlpFormat>,

    // === P0/P1 Features ===
    pub subtitles: Vec<SubtitleInfo>,           // Available manual subtitles
    pub automatic_captions: Vec<SubtitleInfo>,  // Auto-generated captions
    pub chapters: Vec<ChapterInfo>,             // Video chapters
    pub is_live: bool,                          // Live stream indicator
    pub live_status: Option<String>,            // is_live, was_live, is_upcoming
}

/// Subtitle track information
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SubtitleInfo {
    pub lang: String,           // Language code: "en", "vi", "auto"
    pub lang_name: Option<String>, // Language name: "English", "Vietnamese"
    pub ext: String,            // Format: "srt", "vtt", "ass"
    pub url: Option<String>,    // Download URL (if available)
}

/// Chapter information
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ChapterInfo {
    pub title: String,
    pub start_time: f64,        // Start time in seconds
    pub end_time: f64,          // End time in seconds
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct YtDlpFormat {
    pub format_id: String,
    pub ext: String,
    pub resolution: Option<String>,
    pub height: Option<u32>,
    pub width: Option<u32>,
    pub filesize: Option<u64>,
    pub vcodec: Option<String>,
    pub acodec: Option<String>,
    pub fps: Option<f64>,
    pub tbr: Option<f64>,               // total bitrate
    pub format_note: Option<String>,    // e.g., "2160p", "1080p60"
}

/// Error types from yt-dlp
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum YtDlpError {
    NotFound,
    GeoRestricted,
    LoginRequired,
    AgeRestricted,
    FormatNotAvailable,
    NetworkError,
    RateLimited,
    /// External JavaScript runtime (Deno) is missing or unhealthy. Surfaced
    /// when yt-dlp 2025.11.12+ cannot solve YouTube nsig / n-challenge.
    /// Must be classified BEFORE LoginRequired because YouTube often emits
    /// "Sign in to confirm…" hints alongside nsig errors; mis-routing to
    /// login triggers a useless cookie-refresh loop while the real fix is
    /// to re-acquire / re-install Deno.
    JsRuntimeUnavailable,
    Unknown(String),
}

// Regex patterns for parsing yt-dlp output
// Example: [download]  45.2% of 12.34MiB at 1.23MiB/s ETA 00:05
static PROGRESS_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[download\]\s+(\d+\.?\d*)%(?:\s+of\s+~?([\d.]+)(\w+))?(?:\s+at\s+([\d.]+)(\w+)/s)?(?:\s+ETA\s+(\d+:\d+(?::\d+)?))?").unwrap()
});

// Example: [download] Destination: video.mp4
static DESTINATION_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[download\]\s+Destination:\s+(.+)").unwrap()
});

// Example: [download] 100% of 12.34MiB in 00:05
static FINISHED_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\[download\]\s+100%\s+of").unwrap()
});

// Error patterns
static ERROR_UNAVAILABLE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(video unavailable|this video is not available|removed|deleted)").unwrap()
});

static ERROR_GEO: LazyLock<Regex> = LazyLock::new(|| {
    // Matches both shapes of YouTube's geo-block stderr:
    //   * "not available in your country" (direct negation)
    //   * "The uploader has not made this video available in your country"
    //     (passive form — three words between "not" and "available")
    // The `{0,5}` upper bound on the intervening word run prevents the
    // pattern from matching unrelated sentences that happen to contain
    // "not" early and "available in your country" much later in stderr.
    Regex::new(
        r"(?i)(geo[- ]?restricted|not(?:\s+\w+){0,5}\s+available\s+in\s+your\s+country|blocked\s+in\s+your)",
    )
    .unwrap()
});

static ERROR_LOGIN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(login required|sign in|private video|members[- ]?only)").unwrap()
});

/// JS runtime (Deno) absence / failure markers. Must be evaluated BEFORE
/// `ERROR_LOGIN` because YouTube emits "Sign in to confirm..." hints in
/// the same stderr block as nsig errors when Deno is missing — login
/// classification then routes the user into a useless cookie-refresh
/// loop instead of surfacing the real Deno install / network failure.
/// Patterns mirror Dart `_looksLikeJsRuntimeIssue` (`ytdlp_datasource.dart`).
static ERROR_JS_RUNTIME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?i)(n challenge solving failed|signature solving failed|external javascript runtime|no usable javascript runtime|could not find any usable javascript|deno:[^\n]*(not found|command not found|no such file))",
    )
    .unwrap()
});

static ERROR_AGE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(age[- ]?restricted|age verification|confirm your age)").unwrap()
});

static ERROR_RATE_LIMIT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(rate[- ]?limit|too many requests|429)").unwrap()
});

impl YtDlpProgress {
    pub fn new() -> Self {
        Self {
            percent: 0.0,
            downloaded_bytes: None,
            total_bytes: None,
            speed: None,
            eta_seconds: None,
            status: YtDlpStatus::Downloading,
        }
    }
}

impl Default for YtDlpProgress {
    fn default() -> Self {
        Self::new()
    }
}

/// Parse a single line of yt-dlp output
pub fn parse_progress_line(line: &str) -> Option<YtDlpProgress> {
    // Check for finished download
    if FINISHED_REGEX.is_match(line) {
        return Some(YtDlpProgress {
            percent: 100.0,
            downloaded_bytes: None,
            total_bytes: None,
            speed: None,
            eta_seconds: None,
            status: YtDlpStatus::Finished,
        });
    }

    // Parse progress line
    if let Some(caps) = PROGRESS_REGEX.captures(line) {
        let percent: f64 = caps.get(1)?.as_str().parse().ok()?;

        let total_bytes = if let (Some(size), Some(unit)) = (caps.get(2), caps.get(3)) {
            Some(parse_size_to_bytes(size.as_str(), unit.as_str()))
        } else {
            None
        };

        let speed = if let (Some(spd), Some(unit)) = (caps.get(4), caps.get(5)) {
            Some(parse_size_to_bytes(spd.as_str(), unit.as_str()) as f64)
        } else {
            None
        };

        let eta_seconds = caps.get(6).and_then(|m| parse_eta_to_seconds(m.as_str()));

        let downloaded_bytes = total_bytes.map(|t| (t as f64 * percent / 100.0) as u64);

        return Some(YtDlpProgress {
            percent,
            downloaded_bytes,
            total_bytes,
            speed,
            eta_seconds,
            status: YtDlpStatus::Downloading,
        });
    }

    // Check for post-processing — but NOT error lines.
    // yt-dlp outputs both "[ffmpeg] Merging formats..." (success) and
    // "[ffmpeg] Error opening file..." (failure) — must distinguish them.
    if line.contains("[Merger]") || line.contains("[ffmpeg]") || line.contains("[ExtractAudio]") {
        let lower = line.to_lowercase();
        if lower.contains("error") || lower.contains("failed") || lower.contains("not found")
            || lower.contains("permission denied") || lower.contains("access denied")
            || lower.contains("no such file") || lower.contains("invalid") {
            return Some(YtDlpProgress {
                percent: 100.0,
                status: YtDlpStatus::Error,
                ..Default::default()
            });
        }
        return Some(YtDlpProgress {
            percent: 100.0,
            status: YtDlpStatus::PostProcessing,
            ..Default::default()
        });
    }

    None
}

/// Parse error from yt-dlp stderr
///
/// Precedence note: JS-runtime detection MUST come first. yt-dlp surfaces
/// nsig / n-challenge failures alongside YouTube's "Sign in to confirm..."
/// bot-check warnings, and the `ERROR_LOGIN` regex matches the latter. If
/// login wins, the host app drives the user into a cookie-refresh / login
/// loop that cannot recover the underlying Deno failure (production
/// telemetry: loginRequired 52/24h, partially these mis-classifications).
pub fn parse_error(stderr: &str) -> YtDlpError {
    if ERROR_JS_RUNTIME.is_match(stderr) {
        YtDlpError::JsRuntimeUnavailable
    } else if ERROR_UNAVAILABLE.is_match(stderr) {
        YtDlpError::NotFound
    } else if ERROR_GEO.is_match(stderr) {
        YtDlpError::GeoRestricted
    } else if ERROR_AGE.is_match(stderr) {
        // AGE before LOGIN: YouTube's age-restriction stderr is
        // "Sign in to confirm your age" — the ERROR_LOGIN `sign in`
        // alternative would otherwise win and the host app would push the
        // user into the regular cookie-refresh flow, which cannot satisfy
        // the age gate. Specificity wins precedence.
        YtDlpError::AgeRestricted
    } else if ERROR_LOGIN.is_match(stderr) {
        YtDlpError::LoginRequired
    } else if ERROR_RATE_LIMIT.is_match(stderr) {
        YtDlpError::RateLimited
    } else if stderr.contains("No video formats found") || stderr.contains("format not available") {
        YtDlpError::FormatNotAvailable
    } else if stderr.contains("Unable to download") || stderr.contains("Connection refused") {
        YtDlpError::NetworkError
    } else {
        YtDlpError::Unknown(stderr.lines().last().unwrap_or(stderr).to_string())
    }
}

/// Sanitize optional string to prevent UTF-8 encoding errors
/// This fixes RangeError in flutter_rust_bridge serialization
fn sanitize_optional_string(s: Option<String>) -> Option<String> {
    s.and_then(|text| {
        // Convert to bytes and replace invalid UTF-8 sequences
        let sanitized = text
            .chars()
            .filter(|c| {
                // Keep only valid Unicode characters that won't cause serialization issues
                // Remove control characters except newline/tab
                !c.is_control() || *c == '\n' || *c == '\t'
            })
            .collect::<String>();
        
        // Return None if empty after sanitization
        if sanitized.is_empty() {
            None
        } else {
            Some(sanitized)
        }
    })
}

/// Convert i64 to u64, returning None for negative values
/// yt-dlp returns -1 for unknown/unavailable numeric values
fn i64_to_u64(val: Option<i64>) -> Option<u64> {
    val.and_then(|v| if v >= 0 { Some(v as u64) } else { None })
}

/// Convert i32 to u32, returning None for negative values
fn i32_to_u32(val: Option<i32>) -> Option<u32> {
    val.and_then(|v| if v >= 0 { Some(v as u32) } else { None })
}

/// Parse video info from JSON output
pub fn parse_video_info(json_str: &str) -> Result<YtDlpVideoInfo, serde_json::Error> {
    // Use i64/i32 for parsing to handle negative values from yt-dlp
    // yt-dlp returns -1 for unknown/unavailable values on some platforms
    #[derive(Deserialize)]
    struct RawInfo {
        id: Option<String>,
        title: Option<String>,
        description: Option<String>,
        uploader: Option<String>,
        uploader_id: Option<String>,
        duration: Option<f64>,
        view_count: Option<i64>,      // Can be -1
        like_count: Option<i64>,      // Can be -1
        upload_date: Option<String>,
        thumbnail: Option<String>,
        webpage_url: Option<String>,
        extractor: Option<String>,
        formats: Option<Vec<RawFormat>>,
        // P0/P1 fields
        subtitles: Option<std::collections::HashMap<String, Vec<RawSubtitle>>>,
        automatic_captions: Option<std::collections::HashMap<String, Vec<RawSubtitle>>>,
        chapters: Option<Vec<RawChapter>>,
        is_live: Option<bool>,
        live_status: Option<String>,
    }

    #[derive(Deserialize)]
    struct RawFormat {
        format_id: Option<String>,
        ext: Option<String>,
        resolution: Option<String>,
        height: Option<i32>,          // Can be -1
        width: Option<i32>,           // Can be -1
        filesize: Option<i64>,        // Can be -1
        filesize_approx: Option<i64>, // Can be -1
        vcodec: Option<String>,
        acodec: Option<String>,
        fps: Option<f64>,
        tbr: Option<f64>,
        format_note: Option<String>,
    }

    #[derive(Deserialize)]
    struct RawSubtitle {
        ext: Option<String>,
        url: Option<String>,
        name: Option<String>,
    }

    #[derive(Deserialize)]
    struct RawChapter {
        title: Option<String>,
        start_time: Option<f64>,
        end_time: Option<f64>,
    }

    let raw: RawInfo = serde_json::from_str(json_str)?;

    // Parse subtitles from HashMap to Vec
    let subtitles = raw.subtitles.unwrap_or_default()
        .into_iter()
        .flat_map(|(lang, subs)| {
            subs.into_iter().map(move |s| SubtitleInfo {
                lang: lang.clone(),
                lang_name: s.name,
                ext: s.ext.unwrap_or_else(|| "vtt".to_string()),
                url: s.url,
            })
        })
        .collect();

    // Parse automatic captions
    let automatic_captions = raw.automatic_captions.unwrap_or_default()
        .into_iter()
        .flat_map(|(lang, subs)| {
            subs.into_iter().map(move |s| SubtitleInfo {
                lang: lang.clone(),
                lang_name: s.name,
                ext: s.ext.unwrap_or_else(|| "vtt".to_string()),
                url: s.url,
            })
        })
        .collect();

    // Parse chapters
    let chapters = raw.chapters.unwrap_or_default()
        .into_iter()
        .map(|c| ChapterInfo {
            title: c.title.unwrap_or_else(|| "Untitled".to_string()),
            start_time: c.start_time.unwrap_or(0.0),
            end_time: c.end_time.unwrap_or(0.0),
        })
        .collect();

    let formats = raw.formats.unwrap_or_default()
        .into_iter()
        .map(|f| YtDlpFormat {
            format_id: f.format_id.unwrap_or_default(),
            ext: f.ext.unwrap_or_default(),
            resolution: sanitize_optional_string(f.resolution),
            height: i32_to_u32(f.height),
            width: i32_to_u32(f.width),
            filesize: i64_to_u64(f.filesize).or(i64_to_u64(f.filesize_approx)),
            vcodec: sanitize_optional_string(f.vcodec),
            acodec: sanitize_optional_string(f.acodec),
            fps: f.fps,
            tbr: f.tbr,
            format_note: sanitize_optional_string(f.format_note),
        })
        .collect();

    Ok(YtDlpVideoInfo {
        id: raw.id.unwrap_or_default(),
        title: raw.title.unwrap_or_default(),
        description: sanitize_optional_string(raw.description),
        uploader: sanitize_optional_string(raw.uploader),
        uploader_id: sanitize_optional_string(raw.uploader_id),
        duration: raw.duration.map(|d| d.max(0.0) as u64), // Ensure non-negative
        view_count: i64_to_u64(raw.view_count),
        like_count: i64_to_u64(raw.like_count),
        upload_date: sanitize_optional_string(raw.upload_date),
        thumbnail: sanitize_optional_string(raw.thumbnail),
        webpage_url: sanitize_optional_string(raw.webpage_url),
        extractor: sanitize_optional_string(raw.extractor),
        formats,
        // P0/P1 fields
        subtitles,
        automatic_captions,
        chapters,
        is_live: raw.is_live.unwrap_or(false),
        live_status: raw.live_status,
    })
}

/// Parse YouTube search results from yt-dlp JSON lines output
/// Each line is a separate JSON object for flat-playlist mode
pub fn parse_search_results(output: &str) -> Vec<YouTubeSearchResult> {
    // yt-dlp outputs one JSON object per line with --flat-playlist
    output
        .lines()
        .filter(|line| !line.is_empty() && line.trim().starts_with('{'))
        .filter_map(|line| parse_single_search_result(line).ok())
        .filter(|r| !r.id.is_empty()) // Filter out empty/invalid results
        .collect()
}

/// Parse a single search result JSON line
fn parse_single_search_result(json_str: &str) -> Result<YouTubeSearchResult, serde_json::Error> {
    #[derive(Deserialize)]
    struct RawSearchResult {
        id: Option<String>,
        title: Option<String>,
        channel: Option<String>,
        uploader: Option<String>,          // Fallback for channel
        channel_id: Option<String>,
        uploader_id: Option<String>,       // Fallback for channel_id
        thumbnail: Option<String>,
        thumbnails: Option<Vec<RawThumbnail>>,
        duration: Option<f64>,
        view_count: Option<i64>,
        upload_date: Option<String>,
        url: Option<String>,
        webpage_url: Option<String>,       // Fallback for url
        description: Option<String>,
        #[serde(rename = "_type")]
        entry_type: Option<String>,
    }

    #[derive(Deserialize)]
    struct RawThumbnail {
        url: Option<String>,
        preference: Option<i32>,
    }

    let raw: RawSearchResult = serde_json::from_str(json_str)?;

    // Skip playlist entries (we only want videos)
    // Return empty result that will be filtered out
    if raw.entry_type.as_deref() == Some("playlist") {
        return Ok(YouTubeSearchResult::default());
    }

    // Skip if no ID (invalid entry)
    if raw.id.is_none() || raw.id.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        return Ok(YouTubeSearchResult::default());
    }

    // Get best thumbnail (prefer higher quality)
    let thumbnail = raw.thumbnail.or_else(|| {
        raw.thumbnails.and_then(|thumbs| {
            thumbs
                .into_iter()
                .max_by_key(|t| t.preference.unwrap_or(0))
                .and_then(|t| t.url)
        })
    });

    // Build full YouTube URL from video ID
    let video_id = raw.id.clone().unwrap_or_default();
    let url = raw.url
        .or(raw.webpage_url)
        .unwrap_or_else(|| format!("https://www.youtube.com/watch?v={}", video_id));

    Ok(YouTubeSearchResult {
        id: video_id,
        title: raw.title.unwrap_or_default(),
        channel: sanitize_optional_string(raw.channel.or(raw.uploader)),
        channel_id: sanitize_optional_string(raw.channel_id.or(raw.uploader_id)),
        thumbnail: sanitize_optional_string(thumbnail),
        duration: raw.duration.map(|d| d.max(0.0) as u64),
        view_count: i64_to_u64(raw.view_count),
        upload_date: sanitize_optional_string(raw.upload_date),
        url,
        description: sanitize_optional_string(raw.description),
    })
}

/// Parse playlist information from yt-dlp --flat-playlist output
/// Returns (PlaylistInfo, Vec<PlaylistVideo>)
/// First line is playlist metadata, remaining lines are video entries
pub fn parse_playlist_info(output: &str) -> Result<(PlaylistInfo, Vec<PlaylistVideo>), serde_json::Error> {
    #[derive(Deserialize)]
    struct RawPlaylistEntry {
        #[serde(rename = "_type")]
        entry_type: Option<String>,
        id: Option<String>,
        title: Option<String>,
        uploader: Option<String>,
        uploader_id: Option<String>,
        thumbnail: Option<String>,
        thumbnails: Option<Vec<RawThumbnail>>,
        description: Option<String>,
        webpage_url: Option<String>,
        url: Option<String>,
        duration: Option<f64>,
        channel: Option<String>,
        channel_id: Option<String>,
        view_count: Option<i64>,
        upload_date: Option<String>,
        playlist_count: Option<u32>,
    }

    #[derive(Deserialize)]
    struct RawThumbnail {
        url: Option<String>,
        preference: Option<i32>,
    }

    let lines: Vec<&str> = output
        .lines()
        .filter(|l| !l.is_empty() && l.trim().starts_with('{'))
        .collect();

    if lines.is_empty() {
        return Ok((PlaylistInfo::default(), vec![]));
    }

    // With --flat-playlist, all lines are videos with embedded playlist info
    // Extract playlist metadata from first video entry
    let first_video: RawPlaylistEntry = serde_json::from_str(lines[0])?;

    // Use playlist_* fields (not video fields) for playlist info
    let playlist_title = first_video.title.as_deref()
        .filter(|t| first_video.entry_type.as_deref() == Some("playlist"))
        .map(|s| s.to_string())
        .or_else(|| {
            // For flat playlists, first video contains playlist info in playlist_* fields
            // But we extract it from the embedded fields
            serde_json::from_str::<serde_json::Value>(lines[0])
                .ok()
                .and_then(|v| v.get("playlist_title").and_then(|t| t.as_str()).map(|s| s.to_string()))
        })
        .unwrap_or_default();

    let playlist_id = serde_json::from_str::<serde_json::Value>(lines[0])
        .ok()
        .and_then(|v| v.get("playlist_id").and_then(|t| t.as_str()).map(|s| s.to_string()))
        .unwrap_or_default();

    let playlist_info = PlaylistInfo {
        id: playlist_id,
        title: playlist_title,
        uploader: None,
        uploader_id: None,
        thumbnail: None,
        description: None,
        video_count: first_video.playlist_count,
        webpage_url: serde_json::from_str::<serde_json::Value>(lines[0])
            .ok()
            .and_then(|v| v.get("playlist_webpage_url").and_then(|t| t.as_str()).map(|s| s.to_string()))
            .unwrap_or_default(),
    };

    // Parse ALL lines as video entries (don't skip first one!)
    let videos: Vec<PlaylistVideo> = lines
        .iter()
        .filter_map(|line| {
            let raw: RawPlaylistEntry = serde_json::from_str(line).ok()?;

            // Skip playlist entries (nested playlists), but keep "url" type (videos)
            if raw.entry_type.as_deref() == Some("playlist") {
                return None;
            }

            // Skip if no ID
            let video_id = raw.id.clone().unwrap_or_default();
            if video_id.is_empty() {
                return None;
            }

            // Get best thumbnail
            let thumbnail = raw.thumbnail.or_else(|| {
                raw.thumbnails.and_then(|thumbs| {
                    thumbs
                        .into_iter()
                        .max_by_key(|t| t.preference.unwrap_or(0))
                        .and_then(|t| t.url)
                })
            });

            // Build full YouTube URL
            let url = raw.url
                .or(raw.webpage_url)
                .unwrap_or_else(|| format!("https://www.youtube.com/watch?v={}", video_id));

            Some(PlaylistVideo {
                id: video_id,
                title: raw.title.unwrap_or_default(),
                url,
                thumbnail: sanitize_optional_string(thumbnail),
                duration: raw.duration.map(|d| d.max(0.0) as u64),
                channel: sanitize_optional_string(raw.channel.or(raw.uploader)),
                channel_id: sanitize_optional_string(raw.channel_id.or(raw.uploader_id)),
                view_count: i64_to_u64(raw.view_count),
                upload_date: sanitize_optional_string(raw.upload_date),
            })
        })
        .collect();

    Ok((playlist_info, videos))
}

/// Parse YouTube channel info and videos from yt-dlp --flat-playlist output
/// Takes the original URL to extract channel ID as authoritative source
/// Returns (ChannelInfo, Vec<PlaylistVideo>)
pub fn parse_channel_info(output: &str, original_url: &str) -> Result<(ChannelInfo, Vec<PlaylistVideo>), serde_json::Error> {
    #[derive(Deserialize)]
    struct RawChannelEntry {
        #[serde(rename = "_type")]
        entry_type: Option<String>,
        id: Option<String>,
        title: Option<String>,
        uploader: Option<String>,
        uploader_id: Option<String>,
        thumbnail: Option<String>,
        thumbnails: Option<Vec<RawThumbnail>>,
        description: Option<String>,
        webpage_url: Option<String>,
        url: Option<String>,
        duration: Option<f64>,
        channel: Option<String>,
        channel_id: Option<String>,
        view_count: Option<i64>,
        upload_date: Option<String>,
        channel_follower_count: Option<i64>,
    }

    #[derive(Deserialize)]
    struct RawThumbnail {
        url: Option<String>,
        preference: Option<i32>,
    }

    let lines: Vec<&str> = output
        .lines()
        .filter(|l| !l.is_empty() && l.trim().starts_with('{'))
        .collect();

    if lines.is_empty() {
        return Ok((ChannelInfo::default(), vec![]));
    }

    // Extract channel metadata from first video entry
    let first_video: RawChannelEntry = serde_json::from_str(lines[0])?;

    // Helper function to get best thumbnail from thumbnails array
    let get_best_thumbnail = |thumbnails: &Option<Vec<RawThumbnail>>| -> Option<String> {
        thumbnails.as_ref().and_then(|thumbs| {
            thumbs
                .iter()
                .max_by_key(|t| t.preference.unwrap_or(0))
                .and_then(|t| t.url.clone())
        })
    };

    // Try to get channel avatar from thumbnails array, fallback to thumbnail field
    let channel_thumbnail = get_best_thumbnail(&first_video.thumbnails)
        .or_else(|| first_video.thumbnail.clone());

    // CRITICAL FIX: Extract channel ID from ALL available sources with priority
    // Priority: 1) video's channel_id, 2) URL extraction, 3) uploader_id
    let channel_id = first_video.channel_id
        .clone()
        .or_else(|| extract_channel_id_from_url(original_url))
        .or_else(|| first_video.uploader_id.clone())
        .unwrap_or_else(|| original_url.to_string()); // Ultimate fallback: use URL itself

    // Extract channel title from video metadata
    let channel_title = first_video.channel
        .clone()
        .or(first_video.uploader.clone())
        .unwrap_or_else(|| extract_channel_name_from_url(original_url));

    // Build channel info with authoritative data
    let channel_info = ChannelInfo {
        id: channel_id.clone(),
        title: channel_title,
        uploader: first_video.uploader.clone(),
        uploader_id: first_video.uploader_id.clone(),
        thumbnail: channel_thumbnail,
        description: first_video.description.clone(),
        subscriber_count: first_video.channel_follower_count.map(|c| c as u64),
        video_count: Some(lines.len() as u32),
        webpage_url: original_url.to_string(), // Use original URL as authoritative source
    };

    // Parse ALL lines as video entries
    let videos: Vec<PlaylistVideo> = lines
        .iter()
        .filter_map(|line| {
            let raw: RawChannelEntry = serde_json::from_str(line).ok()?;

            // Skip playlist entries, only keep videos
            if raw.entry_type.as_deref() == Some("playlist") {
                return None;
            }

            let video_id = raw.id.clone().unwrap_or_default();
            if video_id.is_empty() {
                return None;
            }

            // Get best thumbnail
            let thumbnail = raw.thumbnail.or_else(|| {
                raw.thumbnails.and_then(|thumbs| {
                    thumbs
                        .into_iter()
                        .max_by_key(|t| t.preference.unwrap_or(0))
                        .and_then(|t| t.url)
                })
            });

            // Build full YouTube URL
            let url = raw.url
                .or(raw.webpage_url)
                .unwrap_or_else(|| format!("https://www.youtube.com/watch?v={}", video_id));

            Some(PlaylistVideo {
                id: video_id,
                title: raw.title.unwrap_or_default(),
                url,
                thumbnail,
                duration: raw.duration.map(|d| d as u64),
                channel: raw.channel,
                channel_id: raw.channel_id,
                view_count: raw.view_count.map(|v| v as u64),
                upload_date: raw.upload_date,
            })
        })
        .collect();

    Ok((channel_info, videos))
}

/// Parse YouTube channel metadata from yt-dlp --dump-json output (without --flat-playlist)
/// Extracts accurate channel avatar, banner, and metadata
/// Returns ChannelInfo with accurate thumbnail
pub fn parse_channel_metadata(output: &str) -> Result<ChannelInfo, serde_json::Error> {
    #[derive(Deserialize)]
    struct RawChannelMetadata {
        id: Option<String>,
        channel_id: Option<String>,
        uploader_id: Option<String>,
        title: Option<String>,
        channel: Option<String>,
        uploader: Option<String>,
        description: Option<String>,
        thumbnail: Option<String>,
        thumbnails: Option<Vec<RawThumbnail>>,
        channel_follower_count: Option<i64>,
        channel_follower_count_text: Option<String>,
        webpage_url: Option<String>,
        entries: Option<Vec<serde_json::Value>>, // For playlist-like channels
    }

    #[derive(Deserialize)]
    struct RawThumbnail {
        url: Option<String>,
        preference: Option<i32>,
        id: Option<String>,
    }

    // Parse the JSON output (might be single line or multiple lines)
    let lines: Vec<&str> = output
        .lines()
        .filter(|l| !l.is_empty() && l.trim().starts_with('{'))
        .collect();

    if lines.is_empty() {
        return Ok(ChannelInfo::default());
    }

    // Parse first/only entry as channel metadata
    let raw: RawChannelMetadata = serde_json::from_str(lines[0])?;

    // Helper to get best thumbnail from thumbnails array
    let get_best_thumbnail = |thumbnails: &Option<Vec<RawThumbnail>>| -> Option<String> {
        thumbnails.as_ref().and_then(|thumbs| {
            // Prefer thumbnails with higher preference, or avatars
            thumbs
                .iter()
                .filter(|t| {
                    // Filter for avatar-like thumbnails (not video thumbnails)
                    if let Some(id) = &t.id {
                        id.contains("avatar") || id.contains("channel")
                    } else {
                        true
                    }
                })
                .max_by_key(|t| t.preference.unwrap_or(0))
                .and_then(|t| t.url.clone())
                .or_else(|| {
                    // Fallback: just get highest preference
                    thumbs
                        .iter()
                        .max_by_key(|t| t.preference.unwrap_or(0))
                        .and_then(|t| t.url.clone())
                })
        })
    };

    // Extract channel ID (try multiple fields)
    let channel_id = raw.channel_id
        .or(raw.id.clone())
        .or(raw.uploader_id.clone())
        .unwrap_or_default();

    // Extract best thumbnail (prioritize thumbnails array)
    let thumbnail = get_best_thumbnail(&raw.thumbnails)
        .or(raw.thumbnail);

    // Get video count from entries if available
    let video_count = raw.entries.as_ref().map(|e| e.len() as u32);

    // Build channel info
    let channel_info = ChannelInfo {
        id: channel_id.clone(),
        title: raw.channel
            .clone()
            .or(raw.title.clone())
            .or(raw.uploader.clone())
            .unwrap_or_default(),
        uploader: raw.uploader,
        uploader_id: raw.uploader_id,
        thumbnail,
        description: raw.description,
        subscriber_count: raw.channel_follower_count.map(|c| c as u64),
        video_count,
        webpage_url: raw.webpage_url
            .unwrap_or_else(|| {
                if !channel_id.is_empty() {
                    format!("https://www.youtube.com/channel/{}", channel_id)
                } else {
                    String::new()
                }
            }),
    };

    Ok(channel_info)
}

/// Extract channel ID from YouTube URL
/// Supports formats:
/// - https://www.youtube.com/@username → extract from URL path
/// - https://www.youtube.com/channel/UCxxx → extract UCxxx
/// - https://www.youtube.com/c/customname → extract custom name
fn extract_channel_id_from_url(url: &str) -> Option<String> {
    // Handle @username format
    if let Some(at_pos) = url.find("/@") {
        let after_at = &url[at_pos + 2..];
        let end_pos = after_at.find('/').unwrap_or(after_at.len());
        let username = &after_at[..end_pos];
        // Clean query parameters
        let username_clean = username.split('?').next().unwrap_or(username);
        return Some(format!("@{}", username_clean));
    }

    // Handle /channel/UCxxx format
    if let Some(channel_pos) = url.find("/channel/") {
        let after_channel = &url[channel_pos + 9..];
        let end_pos = after_channel.find('/').unwrap_or(after_channel.len());
        let channel_id = &after_channel[..end_pos];
        // Clean query parameters
        let channel_id_clean = channel_id.split('?').next().unwrap_or(channel_id);
        return Some(channel_id_clean.to_string());
    }

    // Handle /c/customname format
    if let Some(c_pos) = url.find("/c/") {
        let after_c = &url[c_pos + 3..];
        let end_pos = after_c.find('/').unwrap_or(after_c.len());
        let custom_name = &after_c[..end_pos];
        // Clean query parameters
        let custom_name_clean = custom_name.split('?').next().unwrap_or(custom_name);
        return Some(custom_name_clean.to_string());
    }

    None
}

/// Extract channel name from YouTube URL for display purposes
/// Returns the username/custom name from the URL
fn extract_channel_name_from_url(url: &str) -> String {
    extract_channel_id_from_url(url)
        .unwrap_or_else(|| "Unknown Channel".to_string())
}

/// Convert size string to bytes
/// Example: "12.34", "MiB" -> 12936037
fn parse_size_to_bytes(size_str: &str, unit: &str) -> u64 {
    let size: f64 = size_str.parse().unwrap_or(0.0);
    let multiplier = match unit.to_uppercase().as_str() {
        "B" => 1.0,
        "KB" | "KIB" => 1024.0,
        "MB" | "MIB" => 1024.0 * 1024.0,
        "GB" | "GIB" => 1024.0 * 1024.0 * 1024.0,
        _ => 1.0,
    };
    (size * multiplier) as u64
}

/// Parse ETA string to seconds
/// Example: "00:05" -> 5, "01:30:00" -> 5400
fn parse_eta_to_seconds(eta: &str) -> Option<u64> {
    let parts: Vec<&str> = eta.split(':').collect();
    match parts.len() {
        2 => {
            let mins: u64 = parts[0].parse().ok()?;
            let secs: u64 = parts[1].parse().ok()?;
            Some(mins * 60 + secs)
        }
        3 => {
            let hours: u64 = parts[0].parse().ok()?;
            let mins: u64 = parts[1].parse().ok()?;
            let secs: u64 = parts[2].parse().ok()?;
            Some(hours * 3600 + mins * 60 + secs)
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_progress_line() {
        let line = "[download]  45.2% of 12.34MiB at 1.23MiB/s ETA 00:05";
        let progress = parse_progress_line(line).unwrap();
        assert!((progress.percent - 45.2).abs() < 0.1);
        assert_eq!(progress.eta_seconds, Some(5));
    }

    #[test]
    fn test_parse_finished_line() {
        let line = "[download] 100% of 12.34MiB in 00:05";
        let progress = parse_progress_line(line).unwrap();
        assert_eq!(progress.percent, 100.0);
        assert_eq!(progress.status, YtDlpStatus::Finished);
    }

    #[test]
    fn test_parse_size_to_bytes() {
        assert_eq!(parse_size_to_bytes("1", "KB"), 1024);
        assert_eq!(parse_size_to_bytes("1", "MiB"), 1024 * 1024);
        // f64 representation of 12.34 is exactly 12.339999999999999857...
        // (the closest double-precision value), so 12.34 * 1048576.0 floors
        // to 12_939_427 — NOT 12_936_037 as the original assertion claimed.
        // The function is IEEE-754-correct; the prior expected value was a
        // hand-computed slip. Use the computed value to make the contract
        // explicit and robust against accidental future drift.
        assert_eq!(
            parse_size_to_bytes("12.34", "MiB"),
            (12.34_f64 * 1024.0 * 1024.0) as u64,
        );
    }

    #[test]
    fn test_parse_eta() {
        assert_eq!(parse_eta_to_seconds("00:05"), Some(5));
        assert_eq!(parse_eta_to_seconds("01:30"), Some(90));
        assert_eq!(parse_eta_to_seconds("01:30:00"), Some(5400));
    }

    #[test]
    fn test_parse_error() {
        assert!(matches!(
            parse_error("ERROR: Video unavailable"),
            YtDlpError::NotFound
        ));
        assert!(matches!(
            parse_error("ERROR: The uploader has not made this video available in your country"),
            YtDlpError::GeoRestricted
        ));
        assert!(matches!(
            parse_error("ERROR: Sign in to confirm your age"),
            YtDlpError::AgeRestricted
        ));
    }

    #[test]
    fn test_parse_error_js_runtime_wins_over_login() {
        // Real yt-dlp 2025.11.x stderr when Deno is missing: surfaces a
        // "Sign in to confirm you're not a bot" hint above the actual nsig
        // failure. Without JS-runtime precedence, this misroutes to login
        // and traps the user in a cookie refresh loop.
        let combined = "WARNING: [youtube] xxx: n challenge solving failed\n\
                        ERROR: [youtube] xxx: Sign in to confirm you're not a bot.";
        assert!(matches!(
            parse_error(combined),
            YtDlpError::JsRuntimeUnavailable
        ));
    }

    #[test]
    fn test_parse_error_js_runtime_variants() {
        for pattern in [
            "WARNING: Signature solving failed: invalid",
            "ERROR: External JavaScript runtime not found",
            "ERROR: No usable JavaScript runtime to solve nsig",
            "ERROR: could not find any usable JavaScript runtime",
            "ERROR: deno: command not found",
            "ERROR: deno: not found",
        ] {
            assert!(
                matches!(parse_error(pattern), YtDlpError::JsRuntimeUnavailable),
                "expected JsRuntimeUnavailable for: {pattern}"
            );
        }
    }

    #[test]
    fn test_parse_error_login_unchanged_without_nsig() {
        // Sanity: login-only stderr (no nsig hints) still classifies as
        // LoginRequired. Make sure the reorder did not over-eagerly route
        // pure-login cases to JsRuntimeUnavailable.
        assert!(matches!(
            parse_error("ERROR: Sign in to confirm you're not a bot. Use --cookies"),
            YtDlpError::LoginRequired
        ));
        assert!(matches!(
            parse_error("ERROR: This is a private video"),
            YtDlpError::LoginRequired
        ));
    }
}
