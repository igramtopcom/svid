import 'package:flutter/material.dart';
import '../enums/audio_codec_preference.dart';
import '../enums/container_format_preference.dart';
import '../enums/download_engine.dart';
import '../enums/fps_preference.dart';
import '../enums/quality_preference.dart';
import '../enums/video_codec_preference.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../../downloads/domain/entities/post_download_action.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';

/// Repository interface for settings
/// Defines the contract for settings data operations
abstract class SettingsRepository {
  /// Load settings from storage
  Future<SettingsState?> loadSettings();

  /// Save complete settings state
  Future<bool> saveSettings(SettingsState settings);

  /// Save download path
  Future<bool> saveDownloadPath(String path);

  /// Save max concurrent downloads
  Future<bool> saveMaxConcurrentDownloads(int count);

  /// Save theme mode
  Future<bool> saveThemeMode(ThemeMode mode);

  /// Save auto start downloads
  Future<bool> saveAutoStartDownloads(bool enabled);

  /// Save auto clipboard detection
  Future<bool> saveAutoClipboardDetection(bool enabled);

  /// Save notifications enabled
  Future<bool> saveNotificationsEnabled(bool enabled);

  /// Save preferred quality
  Future<bool> savePreferredQuality(QualityPreference preference);

  Future<bool> saveDefaultDownloadFileType(DownloadFileType fileType);

  Future<bool> saveDefaultDownloadQualityIntent(
    DownloadQualityIntent qualityIntent,
  );

  Future<bool> saveDefaultDownloadQualityTarget(
    PortableQualityTarget? qualityTarget,
  );

  // yt-dlp settings

  /// Save download engine preference
  Future<bool> saveDownloadEngine(DownloadEngine engine);

  /// Save enable API fallback (yt-dlp fail → Svid API retry)
  Future<bool> saveEnableApiFallback(bool enabled);

  /// Save show download method badge in UI
  Future<bool> saveShowDownloadMethodBadge(bool enabled);

  /// Save auto-update yt-dlp
  Future<bool> saveAutoUpdateYtdlp(bool enabled);

  /// Save yt-dlp timeout
  Future<bool> saveYtdlpTimeout(int seconds);

  // Format preferences

  /// Save video codec preference
  Future<bool> saveVideoCodecPreference(VideoCodecPreference preference);

  /// Save audio codec preference
  Future<bool> saveAudioCodecPreference(AudioCodecPreference preference);

  /// Save container format preference
  Future<bool> saveContainerFormatPreference(
    ContainerFormatPreference preference,
  );

  /// Save FPS preference
  Future<bool> saveFpsPreference(FpsPreference preference);

  /// Save max resolution
  Future<bool> saveMaxResolution(int resolution);

  // === P0 Features ===

  /// Save subtitles enabled
  Future<bool> saveSubtitlesEnabled(bool enabled);

  /// Save subtitles languages
  Future<bool> saveSubtitlesLanguages(List<String> languages);

  /// Save subtitles format
  Future<bool> saveSubtitlesFormat(String format);

  /// Save embed subtitles
  Future<bool> saveEmbedSubtitles(bool enabled);

  /// Save include auto-translated subtitles
  Future<bool> saveIncludeAutoSubs(bool enabled);

  /// Save write thumbnail
  Future<bool> saveWriteThumbnail(bool enabled);

  /// Save embed thumbnail
  Future<bool> saveEmbedThumbnail(bool enabled);

  /// Save embed metadata
  Future<bool> saveEmbedMetadata(bool enabled);

  /// Save embed chapters
  Future<bool> saveEmbedChapters(bool enabled);

  /// Save SponsorBlock enabled
  Future<bool> saveSponsorBlockEnabled(bool enabled);

  /// Save SponsorBlock action
  Future<bool> saveSponsorBlockAction(String action);

  /// Save SponsorBlock categories
  Future<bool> saveSponsorBlockCategories(List<String> categories);

  // === P1 Features ===

  /// Save force remux
  Future<bool> saveForceRemux(bool enabled);

  // === P2 Features ===

  /// Save TikTok remove watermark
  Future<bool> saveTiktokRemoveWatermark(bool enabled);

  // === P3 Features ===

  /// Save proxy URL
  Future<bool> saveProxyUrl(String? url);

  /// Save proxy list (for round-robin rotation)
  Future<bool> saveProxyList(List<String> proxies);

  /// Save geo-bypass enabled
  Future<bool> saveGeoBypass(bool enabled);

  /// Save geo-bypass country
  Future<bool> saveGeoBypassCountry(String? country);

  /// Save archive enabled
  Future<bool> saveArchiveEnabled(bool enabled);

  /// Save auto-retry enabled
  Future<bool> saveAutoRetryEnabled(bool enabled);

  /// Save date after filter
  Future<bool> saveDateAfter(String? date);

  /// Save date before filter
  Future<bool> saveDateBefore(String? date);

  /// Save min duration filter
  Future<bool> saveMinDuration(int? seconds);

  /// Save max duration filter
  Future<bool> saveMaxDuration(int? seconds);

  // === Network Tuning ===

  /// Save socket timeout
  Future<bool> saveSocketTimeout(int seconds);

  /// Save max retries
  Future<bool> saveMaxRetries(int retries);

  /// Save HTTP chunk size in MB
  Future<bool> saveHttpChunkSizeMb(int sizeMb);

  /// Save max segments for multi-segment parallel download
  Future<bool> saveMaxSegments(int segments);

  // === Output Filename Template ===

  /// Save filename template
  Future<bool> saveFilenameTemplate(String template);

  // === Custom Postprocessor Args ===

  /// Save custom postprocessor args
  Future<bool> saveCustomPostprocessorArgs(String args);

  /// Save downloads view mode
  Future<bool> saveDownloadsViewMode(String mode);

  // === Post-Download Actions ===

  /// Save post-download action
  Future<bool> savePostDownloadAction(PostDownloadAction action);

  /// Save post-download target folder
  Future<bool> savePostDownloadTargetFolder(String folder);

  // === Player Settings ===

  /// Save background audio enabled
  Future<bool> saveBackgroundAudioEnabled(bool enabled);

  /// Save system PiP enabled
  Future<bool> saveSystemPipEnabled(bool enabled);

  // === Bandwidth Limiting ===

  /// Save global bandwidth limit in KB/s (0 = unlimited)
  Future<bool> saveGlobalBandwidthLimit(int kbps);

  // === WiFi-Only Mode ===

  /// Save WiFi-only download mode
  Future<bool> saveWifiOnlyMode(bool enabled);

  // === Auto-Throttle ===

  /// Save auto-throttle mode (adjusts concurrency based on aggregate speed)
  Future<bool> saveAutoThrottle(bool enabled);

  // === Adaptive Segments ===

  /// Save adaptive segments mode (auto-selects numSegments based on bandwidth)
  Future<bool> saveAdaptiveSegments(bool enabled);

  // === Smart Queue ===

  /// Save network-aware queue reorder toggle.
  Future<bool> saveNetworkAwareQueueReorder(bool enabled);

  // === Quiet Hours ===

  /// Save quiet hours enabled flag.
  Future<bool> saveQuietHoursEnabled(bool enabled);

  /// Save quiet hours start hour (0–23).
  Future<bool> saveQuietHoursStart(int hour);

  /// Save quiet hours end hour (0–23).
  Future<bool> saveQuietHoursEnd(int hour);

  /// Save quiet hours bandwidth cap in KB/s.
  Future<bool> saveQuietHoursBandwidthKbps(int kbps);

  /// Clear all settings
  Future<bool> clearSettings();
}
