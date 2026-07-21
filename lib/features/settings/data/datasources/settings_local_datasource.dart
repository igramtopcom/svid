import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../domain/entities/platform_quality_preference.dart';
import '../../domain/enums/audio_codec_preference.dart';
import '../../domain/enums/container_format_preference.dart';
import '../../domain/enums/download_engine.dart';
import '../../domain/enums/fps_preference.dart';
import '../../domain/enums/quality_preference.dart';
import '../../domain/enums/video_codec_preference.dart';
import '../../../downloads/domain/entities/post_download_action.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';

/// Local data source for settings using SharedPreferences
/// Handles persistent storage of user settings
class SettingsLocalDatasource {
  static const String _keyDownloadPath = 'settings_download_path';
  static const String _keyMaxConcurrentDownloads =
      'settings_max_concurrent_downloads';
  static const String _keyThemeMode = 'settings_theme_mode';
  static const String _keyAutoStartDownloads = 'settings_auto_start_downloads';
  static const String _keyAutoClipboardDetection =
      'settings_auto_clipboard_detection';
  static const String _keyNotificationsEnabled =
      'settings_notifications_enabled';
  static const String _keyPreferredQuality = 'settings_preferred_quality';
  static const String _keyDefaultDownloadFileType =
      'settings_default_download_file_type';
  static const String _keyDefaultDownloadQualityIntent =
      'settings_default_download_quality_intent';
  static const String _keyDefaultDownloadQualityTarget =
      'settings_default_download_quality_target';
  static const String _keyPlatformPreferences = 'settings_platform_preferences';
  // yt-dlp settings keys
  static const String _keyDownloadEngine = 'settings_download_engine';
  static const String _keyEnableApiFallback = 'settings_enable_api_fallback';
  static const String _keyAutoUpdateYtdlp = 'settings_auto_update_ytdlp';
  static const String _keyYtdlpTimeout = 'settings_ytdlp_timeout';
  static const String _keyShowDownloadMethodBadge =
      'settings_show_download_method_badge';
  // Format preference keys
  static const String _keyVideoCodecPreference =
      'settings_video_codec_preference';
  static const String _keyAudioCodecPreference =
      'settings_audio_codec_preference';
  static const String _keyContainerFormatPreference =
      'settings_container_format_preference';
  static const String _keyFpsPreference = 'settings_fps_preference';
  static const String _keyMaxResolution =
      'settings_max_resolution'; // 0 = unlimited

  // === P0 Features: Subtitles ===
  static const String _keySubtitlesEnabled = 'settings_subtitles_enabled';
  static const String _keySubtitlesLanguages = 'settings_subtitles_languages';
  static const String _keySubtitlesFormat = 'settings_subtitles_format';
  static const String _keyEmbedSubtitles = 'settings_embed_subtitles';
  static const String _keyIncludeAutoSubs = 'settings_include_auto_subs';

  // === P0 Features: Thumbnails ===
  static const String _keyWriteThumbnail = 'settings_write_thumbnail';
  static const String _keyEmbedThumbnail = 'settings_embed_thumbnail';

  // === P0 Features: Metadata ===
  static const String _keyEmbedMetadata = 'settings_embed_metadata';
  static const String _keyEmbedChapters = 'settings_embed_chapters';

  // === P0 Features: SponsorBlock ===
  static const String _keySponsorBlockEnabled = 'settings_sponsorblock_enabled';
  static const String _keySponsorBlockAction = 'settings_sponsorblock_action';
  static const String _keySponsorBlockCategories =
      'settings_sponsorblock_categories';

  // === P1 Features: Remux ===
  static const String _keyForceRemux = 'settings_force_remux';

  // === P2 Features: Platform-specific ===
  static const String _keyTiktokRemoveWatermark =
      'settings_tiktok_remove_watermark';

  // === Network Tuning ===
  static const String _keySocketTimeout = 'settings_socket_timeout';
  static const String _keyMaxRetries = 'settings_max_retries';
  static const String _keyHttpChunkSizeMb = 'settings_http_chunk_size_mb';

  // === Output Filename Template ===
  static const String _keyFilenameTemplate = 'settings_filename_template';

  // === Custom Postprocessor Args ===
  static const String _keyCustomPostprocessorArgs =
      'settings_custom_postprocessor_args';

  // === Downloads View Mode ===
  static const String _keyDownloadsViewMode = 'settings_downloads_view_mode';

  // === P3 Features: Power User ===
  static const String _keyProxyUrl = 'settings_proxy_url';
  static const String _keyProxyList =
      'settings_proxy_list'; // newline-separated proxy URLs
  static const String _keyGeoBypass = 'settings_geo_bypass';
  static const String _keyGeoBypassCountry = 'settings_geo_bypass_country';
  static const String _keyArchiveEnabled = 'settings_archive_enabled';
  static const String _keyAutoRetryEnabled = 'settings_auto_retry_enabled';
  static const String _keyDateAfter = 'settings_date_after';
  static const String _keyDateBefore = 'settings_date_before';
  static const String _keyMinDuration = 'settings_min_duration';
  static const String _keyMaxDuration = 'settings_max_duration';

  final SharedPreferences _prefs;

  SettingsLocalDatasource(this._prefs);

  /// Get download path
  String? getDownloadPath() {
    return _prefs.getString(_keyDownloadPath);
  }

  /// Save download path
  Future<bool> saveDownloadPath(String path) async {
    return _prefs.setString(_keyDownloadPath, path);
  }

  /// Get max concurrent downloads
  int? getMaxConcurrentDownloads() {
    return _prefs.getInt(_keyMaxConcurrentDownloads);
  }

  /// Save max concurrent downloads
  Future<bool> saveMaxConcurrentDownloads(int count) async {
    return _prefs.setInt(_keyMaxConcurrentDownloads, count);
  }

  /// Get theme mode
  ThemeMode getThemeMode() {
    final modeString = _prefs.getString(_keyThemeMode);
    if (modeString == null) return ThemeMode.system;

    switch (modeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// Save theme mode
  Future<bool> saveThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
        modeString = 'system';
        break;
    }
    return _prefs.setString(_keyThemeMode, modeString);
  }

  /// Get auto start downloads
  bool getAutoStartDownloads() {
    return _prefs.getBool(_keyAutoStartDownloads) ?? false;
  }

  /// Save auto start downloads
  Future<bool> saveAutoStartDownloads(bool enabled) async {
    return _prefs.setBool(_keyAutoStartDownloads, enabled);
  }

  /// Get auto clipboard detection
  bool getAutoClipboardDetection() {
    return _prefs.getBool(_keyAutoClipboardDetection) ?? true;
  }

  /// Save auto clipboard detection
  Future<bool> saveAutoClipboardDetection(bool enabled) async {
    return _prefs.setBool(_keyAutoClipboardDetection, enabled);
  }

  /// Get notifications enabled
  bool getNotificationsEnabled() {
    return _prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  /// Save notifications enabled
  Future<bool> saveNotificationsEnabled(bool enabled) async {
    return _prefs.setBool(_keyNotificationsEnabled, enabled);
  }

  /// Get preferred quality
  QualityPreference getPreferredQuality() {
    final qualityString = _prefs.getString(_keyPreferredQuality);
    if (qualityString == null) return QualityPreference.auto;
    return QualityPreference.fromDbString(qualityString);
  }

  /// Save preferred quality
  Future<bool> savePreferredQuality(QualityPreference preference) async {
    return _prefs.setString(_keyPreferredQuality, preference.toDbString());
  }

  DownloadFileType? getDefaultDownloadFileType() {
    final value = _prefs.getString(_keyDefaultDownloadFileType);
    if (value == null) return null;
    return DownloadFileType.fromDbString(value);
  }

  Future<bool> saveDefaultDownloadFileType(DownloadFileType fileType) async {
    return _prefs.setString(_keyDefaultDownloadFileType, fileType.toDbString());
  }

  DownloadQualityIntent? getDefaultDownloadQualityIntent() {
    final value = _prefs.getString(_keyDefaultDownloadQualityIntent);
    if (value == null) return null;
    return DownloadQualityIntent.fromDbString(value);
  }

  Future<bool> saveDefaultDownloadQualityIntent(
    DownloadQualityIntent qualityIntent,
  ) async {
    return _prefs.setString(
      _keyDefaultDownloadQualityIntent,
      qualityIntent.toDbString(),
    );
  }

  PortableQualityTarget? getDefaultDownloadQualityTarget() {
    final value = _prefs.getString(_keyDefaultDownloadQualityTarget);
    if (value == null || value.isEmpty) return null;
    try {
      return PortableQualityTarget.fromJson(
        json.decode(value) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveDefaultDownloadQualityTarget(
    PortableQualityTarget? qualityTarget,
  ) async {
    if (qualityTarget == null) {
      return _prefs.remove(_keyDefaultDownloadQualityTarget);
    }
    return _prefs.setString(
      _keyDefaultDownloadQualityTarget,
      json.encode(qualityTarget.toJson()),
    );
  }

  /// Get saved platform quality preferences
  Map<VideoPlatform, PlatformQualityPreference> getPlatformPreferences() {
    final jsonString = _prefs.getString(_keyPlatformPreferences);
    if (jsonString == null || jsonString.isEmpty) return {};

    try {
      final Map<String, dynamic> decoded = json.decode(jsonString);
      final Map<VideoPlatform, PlatformQualityPreference> preferences = {};

      for (var entry in decoded.entries) {
        final platform = VideoPlatform.fromDbString(entry.key);
        final preference = PlatformQualityPreference.fromJson(entry.value);
        preferences[platform] = preference;
      }

      return preferences;
    } catch (e) {
      return {};
    }
  }

  /// Save platform quality preference
  Future<bool> savePlatformPreference(
    VideoPlatform platform,
    PlatformQualityPreference preference,
  ) async {
    final current = getPlatformPreferences();
    current[platform] = preference;

    final Map<String, dynamic> toSave = {};
    for (var entry in current.entries) {
      toSave[entry.key.toDbString()] = entry.value.toJson();
    }

    final jsonString = json.encode(toSave);
    return _prefs.setString(_keyPlatformPreferences, jsonString);
  }

  /// Remove platform preference
  Future<bool> removePlatformPreference(VideoPlatform platform) async {
    final current = getPlatformPreferences();
    current.remove(platform);

    final Map<String, dynamic> toSave = {};
    for (var entry in current.entries) {
      toSave[entry.key.toDbString()] = entry.value.toJson();
    }

    final jsonString = json.encode(toSave);
    return _prefs.setString(_keyPlatformPreferences, jsonString);
  }

  /// Clear all platform preferences
  Future<bool> clearAllPlatformPreferences() async {
    return _prefs.remove(_keyPlatformPreferences);
  }

  // ==================== YT-DLP SETTINGS ====================

  /// Get download engine preference
  DownloadEngine getDownloadEngine() {
    final engineString = _prefs.getString(_keyDownloadEngine);
    if (engineString == null) return DownloadEngine.ytdlpOnly;
    return DownloadEngine.fromString(engineString);
  }

  /// Save download engine preference
  Future<bool> saveDownloadEngine(DownloadEngine engine) async {
    return _prefs.setString(_keyDownloadEngine, engine.name);
  }

  /// Get API fallback enabled
  bool getEnableApiFallback() {
    return _prefs.getBool(_keyEnableApiFallback) ?? false;
  }

  /// Save API fallback enabled
  Future<bool> saveEnableApiFallback(bool enabled) async {
    return _prefs.setBool(_keyEnableApiFallback, enabled);
  }

  /// Get auto-update yt-dlp
  bool getAutoUpdateYtdlp() {
    return _prefs.getBool(_keyAutoUpdateYtdlp) ?? true;
  }

  /// Save auto-update yt-dlp
  Future<bool> saveAutoUpdateYtdlp(bool enabled) async {
    return _prefs.setBool(_keyAutoUpdateYtdlp, enabled);
  }

  /// Get yt-dlp timeout
  int getYtdlpTimeout() {
    return _prefs.getInt(_keyYtdlpTimeout) ?? 30;
  }

  /// Save yt-dlp timeout
  Future<bool> saveYtdlpTimeout(int seconds) async {
    return _prefs.setInt(_keyYtdlpTimeout, seconds);
  }

  /// Get show download method badge
  bool getShowDownloadMethodBadge() {
    return _prefs.getBool(_keyShowDownloadMethodBadge) ?? true;
  }

  /// Save show download method badge
  Future<bool> saveShowDownloadMethodBadge(bool show) async {
    return _prefs.setBool(_keyShowDownloadMethodBadge, show);
  }

  // ==================== FORMAT PREFERENCES ====================

  /// Get video codec preference
  VideoCodecPreference getVideoCodecPreference() {
    final value = _prefs.getString(_keyVideoCodecPreference);
    if (value == null) return VideoCodecPreference.auto;
    return VideoCodecPreference.fromDbString(value);
  }

  /// Save video codec preference
  Future<bool> saveVideoCodecPreference(VideoCodecPreference preference) async {
    return _prefs.setString(_keyVideoCodecPreference, preference.toDbString());
  }

  /// Get audio codec preference
  AudioCodecPreference getAudioCodecPreference() {
    final value = _prefs.getString(_keyAudioCodecPreference);
    if (value == null) return AudioCodecPreference.auto;
    return AudioCodecPreference.fromDbString(value);
  }

  /// Save audio codec preference
  Future<bool> saveAudioCodecPreference(AudioCodecPreference preference) async {
    return _prefs.setString(_keyAudioCodecPreference, preference.toDbString());
  }

  /// Get container format preference
  ContainerFormatPreference getContainerFormatPreference() {
    final value = _prefs.getString(_keyContainerFormatPreference);
    if (value == null) return ContainerFormatPreference.mp4;
    return ContainerFormatPreference.fromDbString(value);
  }

  /// Save container format preference
  Future<bool> saveContainerFormatPreference(
    ContainerFormatPreference preference,
  ) async {
    return _prefs.setString(
      _keyContainerFormatPreference,
      preference.toDbString(),
    );
  }

  /// Get FPS preference
  FpsPreference getFpsPreference() {
    final value = _prefs.getString(_keyFpsPreference);
    if (value == null) return FpsPreference.auto;
    return FpsPreference.fromDbString(value);
  }

  /// Save FPS preference
  Future<bool> saveFpsPreference(FpsPreference preference) async {
    return _prefs.setString(_keyFpsPreference, preference.toDbString());
  }

  /// Get max resolution (0 = unlimited)
  int getMaxResolution() {
    return _prefs.getInt(_keyMaxResolution) ?? 0;
  }

  /// Save max resolution
  Future<bool> saveMaxResolution(int resolution) async {
    return _prefs.setInt(_keyMaxResolution, resolution);
  }

  // ==========================================================================
  // P0 FEATURES: SUBTITLES
  // ==========================================================================

  /// Get subtitles enabled
  bool getSubtitlesEnabled() {
    return _prefs.getBool(_keySubtitlesEnabled) ?? false;
  }

  /// Save subtitles enabled
  Future<bool> saveSubtitlesEnabled(bool enabled) async {
    return _prefs.setBool(_keySubtitlesEnabled, enabled);
  }

  /// Get subtitles languages (e.g., ["en", "vi"])
  List<String> getSubtitlesLanguages() {
    final value = _prefs.getStringList(_keySubtitlesLanguages);
    return value ?? ['en'];
  }

  /// Save subtitles languages
  Future<bool> saveSubtitlesLanguages(List<String> languages) async {
    return _prefs.setStringList(_keySubtitlesLanguages, languages);
  }

  /// Get subtitles format (srt, vtt, ass)
  String getSubtitlesFormat() {
    return _prefs.getString(_keySubtitlesFormat) ?? 'srt';
  }

  /// Save subtitles format
  Future<bool> saveSubtitlesFormat(String format) async {
    return _prefs.setString(_keySubtitlesFormat, format);
  }

  /// Get embed subtitles
  bool getEmbedSubtitles() {
    return _prefs.getBool(_keyEmbedSubtitles) ?? true;
  }

  /// Save embed subtitles
  Future<bool> saveEmbedSubtitles(bool enabled) async {
    return _prefs.setBool(_keyEmbedSubtitles, enabled);
  }

  /// Get include auto-translated subtitles
  bool getIncludeAutoSubs() {
    return _prefs.getBool(_keyIncludeAutoSubs) ?? false;
  }

  /// Save include auto-translated subtitles
  Future<bool> saveIncludeAutoSubs(bool enabled) async {
    return _prefs.setBool(_keyIncludeAutoSubs, enabled);
  }

  // ==========================================================================
  // P0 FEATURES: THUMBNAILS
  // ==========================================================================

  /// Get write thumbnail
  bool getWriteThumbnail() {
    return _prefs.getBool(_keyWriteThumbnail) ?? false;
  }

  /// Save write thumbnail
  Future<bool> saveWriteThumbnail(bool enabled) async {
    return _prefs.setBool(_keyWriteThumbnail, enabled);
  }

  /// Get embed thumbnail
  bool getEmbedThumbnail() {
    return _prefs.getBool(_keyEmbedThumbnail) ?? true;
  }

  /// Save embed thumbnail
  Future<bool> saveEmbedThumbnail(bool enabled) async {
    return _prefs.setBool(_keyEmbedThumbnail, enabled);
  }

  // ==========================================================================
  // P0 FEATURES: METADATA
  // ==========================================================================

  /// Get embed metadata
  bool getEmbedMetadata() {
    return _prefs.getBool(_keyEmbedMetadata) ?? true;
  }

  /// Save embed metadata
  Future<bool> saveEmbedMetadata(bool enabled) async {
    return _prefs.setBool(_keyEmbedMetadata, enabled);
  }

  /// Get embed chapters
  bool getEmbedChapters() {
    return _prefs.getBool(_keyEmbedChapters) ?? true;
  }

  /// Save embed chapters
  Future<bool> saveEmbedChapters(bool enabled) async {
    return _prefs.setBool(_keyEmbedChapters, enabled);
  }

  // ==========================================================================
  // P0 FEATURES: SPONSORBLOCK
  // ==========================================================================

  /// Get SponsorBlock enabled
  bool getSponsorBlockEnabled() {
    return _prefs.getBool(_keySponsorBlockEnabled) ?? false;
  }

  /// Save SponsorBlock enabled
  Future<bool> saveSponsorBlockEnabled(bool enabled) async {
    return _prefs.setBool(_keySponsorBlockEnabled, enabled);
  }

  /// Get SponsorBlock action (skip, remove, chapter)
  String getSponsorBlockAction() {
    return _prefs.getString(_keySponsorBlockAction) ?? 'skip';
  }

  /// Save SponsorBlock action
  Future<bool> saveSponsorBlockAction(String action) async {
    return _prefs.setString(_keySponsorBlockAction, action);
  }

  /// Get SponsorBlock categories
  List<String> getSponsorBlockCategories() {
    final value = _prefs.getStringList(_keySponsorBlockCategories);
    return value ?? ['sponsor'];
  }

  /// Save SponsorBlock categories
  Future<bool> saveSponsorBlockCategories(List<String> categories) async {
    return _prefs.setStringList(_keySponsorBlockCategories, categories);
  }

  // ==========================================================================
  // P1 FEATURES: REMUX
  // ==========================================================================

  /// Get force remux enabled
  bool getForceRemux() {
    return _prefs.getBool(_keyForceRemux) ?? false;
  }

  /// Save force remux enabled
  Future<bool> saveForceRemux(bool enabled) async {
    return _prefs.setBool(_keyForceRemux, enabled);
  }

  // ==========================================================================
  // P2 FEATURES: PLATFORM-SPECIFIC
  // ==========================================================================

  /// Get TikTok remove watermark
  bool getTiktokRemoveWatermark() {
    return _prefs.getBool(_keyTiktokRemoveWatermark) ?? true; // Default ON
  }

  /// Save TikTok remove watermark
  Future<bool> saveTiktokRemoveWatermark(bool enabled) async {
    return _prefs.setBool(_keyTiktokRemoveWatermark, enabled);
  }

  // ==========================================================================
  // P3 FEATURES: POWER USER
  // ==========================================================================

  /// Get proxy URL (null = disabled)
  String? getProxyUrl() {
    return _prefs.getString(_keyProxyUrl);
  }

  /// Save proxy URL (null to disable)
  Future<bool> saveProxyUrl(String? url) async {
    if (url == null || url.isEmpty) {
      return _prefs.remove(_keyProxyUrl);
    }
    return _prefs.setString(_keyProxyUrl, url);
  }

  /// Get proxy list (newline-separated stored value → `List<String>`)
  List<String> getProxyList() {
    final raw = _prefs.getString(_keyProxyList) ?? '';
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Save proxy list (`List<String>` → newline-separated)
  Future<bool> saveProxyList(List<String> proxies) async {
    final raw = proxies
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join('\n');
    if (raw.isEmpty) return _prefs.remove(_keyProxyList);
    return _prefs.setString(_keyProxyList, raw);
  }

  /// Get geo-bypass enabled
  bool getGeoBypass() {
    return _prefs.getBool(_keyGeoBypass) ?? false;
  }

  /// Save geo-bypass enabled
  Future<bool> saveGeoBypass(bool enabled) async {
    return _prefs.setBool(_keyGeoBypass, enabled);
  }

  /// Get geo-bypass country (null = auto)
  String? getGeoBypassCountry() {
    return _prefs.getString(_keyGeoBypassCountry);
  }

  /// Save geo-bypass country (null for auto)
  Future<bool> saveGeoBypassCountry(String? country) async {
    if (country == null || country.isEmpty) {
      return _prefs.remove(_keyGeoBypassCountry);
    }
    return _prefs.setString(_keyGeoBypassCountry, country);
  }

  /// Get archive enabled
  bool getArchiveEnabled() {
    return _prefs.getBool(_keyArchiveEnabled) ?? false;
  }

  /// Save archive enabled
  Future<bool> saveArchiveEnabled(bool enabled) async {
    return _prefs.setBool(_keyArchiveEnabled, enabled);
  }

  /// Get auto-retry enabled (default: true)
  bool getAutoRetryEnabled() {
    return _prefs.getBool(_keyAutoRetryEnabled) ?? true;
  }

  /// Save auto-retry enabled
  Future<bool> saveAutoRetryEnabled(bool enabled) async {
    return _prefs.setBool(_keyAutoRetryEnabled, enabled);
  }

  /// Get date after filter (YYYYMMDD format, null = disabled)
  String? getDateAfter() {
    return _prefs.getString(_keyDateAfter);
  }

  /// Save date after filter (null to disable)
  Future<bool> saveDateAfter(String? date) async {
    if (date == null || date.isEmpty) {
      return _prefs.remove(_keyDateAfter);
    }
    return _prefs.setString(_keyDateAfter, date);
  }

  /// Get date before filter (YYYYMMDD format, null = disabled)
  String? getDateBefore() {
    return _prefs.getString(_keyDateBefore);
  }

  /// Save date before filter (null to disable)
  Future<bool> saveDateBefore(String? date) async {
    if (date == null || date.isEmpty) {
      return _prefs.remove(_keyDateBefore);
    }
    return _prefs.setString(_keyDateBefore, date);
  }

  /// Get min duration filter (seconds, null = disabled)
  int? getMinDuration() {
    return _prefs.getInt(_keyMinDuration);
  }

  /// Save min duration filter (null to disable)
  Future<bool> saveMinDuration(int? seconds) async {
    if (seconds == null) {
      return _prefs.remove(_keyMinDuration);
    }
    return _prefs.setInt(_keyMinDuration, seconds);
  }

  /// Get max duration filter (seconds, null = disabled)
  int? getMaxDuration() {
    return _prefs.getInt(_keyMaxDuration);
  }

  /// Save max duration filter (null to disable)
  Future<bool> saveMaxDuration(int? seconds) async {
    if (seconds == null) {
      return _prefs.remove(_keyMaxDuration);
    }
    return _prefs.setInt(_keyMaxDuration, seconds);
  }

  // ==========================================================================
  // NETWORK TUNING
  // ==========================================================================

  /// Get socket timeout (seconds, default 30)
  int getSocketTimeout() {
    return _prefs.getInt(_keySocketTimeout) ?? 30;
  }

  /// Save socket timeout
  Future<bool> saveSocketTimeout(int seconds) async {
    return _prefs.setInt(_keySocketTimeout, seconds);
  }

  /// Get max retries (default 3)
  int getMaxRetries() {
    return _prefs.getInt(_keyMaxRetries) ?? 3;
  }

  /// Save max retries
  Future<bool> saveMaxRetries(int retries) async {
    return _prefs.setInt(_keyMaxRetries, retries);
  }

  /// Get HTTP chunk size in MB (default 10)
  int getHttpChunkSizeMb() {
    return _prefs.getInt(_keyHttpChunkSizeMb) ?? 10;
  }

  /// Save HTTP chunk size in MB
  Future<bool> saveHttpChunkSizeMb(int sizeMb) async {
    return _prefs.setInt(_keyHttpChunkSizeMb, sizeMb);
  }

  // ==========================================================================
  // MULTI-SEGMENT DOWNLOAD
  // ==========================================================================

  static const _keyMaxSegments = 'max_segments';

  /// Get max segments for parallel download (default 4, range 1-16)
  int getMaxSegments() {
    return _prefs.getInt(_keyMaxSegments) ?? 4;
  }

  /// Save max segments
  Future<bool> saveMaxSegments(int segments) async {
    return _prefs.setInt(_keyMaxSegments, segments.clamp(1, 16));
  }

  // ==========================================================================
  // OUTPUT FILENAME TEMPLATE
  // ==========================================================================

  /// Get filename template (default '%(title)s.%(ext)s')
  String getFilenameTemplate() {
    return _prefs.getString(_keyFilenameTemplate) ?? '%(title)s.%(ext)s';
  }

  /// Save filename template
  Future<bool> saveFilenameTemplate(String template) async {
    return _prefs.setString(_keyFilenameTemplate, template);
  }

  // ==========================================================================
  // CUSTOM POSTPROCESSOR ARGS
  // ==========================================================================

  /// Get custom postprocessor args (default empty)
  String getCustomPostprocessorArgs() {
    return _prefs.getString(_keyCustomPostprocessorArgs) ?? '';
  }

  /// Save custom postprocessor args
  Future<bool> saveCustomPostprocessorArgs(String args) async {
    if (args.isEmpty) {
      return _prefs.remove(_keyCustomPostprocessorArgs);
    }
    return _prefs.setString(_keyCustomPostprocessorArgs, args);
  }

  // ==========================================================================
  // DOWNLOADS VIEW MODE
  // ==========================================================================

  /// Get downloads view mode ('list' or 'grid')
  String getDownloadsViewMode() {
    return _prefs.getString(_keyDownloadsViewMode) ?? 'list';
  }

  /// Save downloads view mode
  Future<bool> saveDownloadsViewMode(String mode) async {
    return _prefs.setString(_keyDownloadsViewMode, mode);
  }

  // ==========================================================================
  // PLAYER SETTINGS
  // ==========================================================================

  static const _keyBackgroundAudioEnabled = 'settings_background_audio_enabled';
  static const _keySystemPipEnabled = 'settings_system_pip_enabled';
  static const _legacyKeySystemPipEnabled = 'system_pip_enabled';

  /// Get background audio enabled (default true — audio keeps playing when window loses focus)
  bool getBackgroundAudioEnabled() {
    return _prefs.getBool(_keyBackgroundAudioEnabled) ?? true;
  }

  /// Save background audio enabled
  Future<bool> saveBackgroundAudioEnabled(bool enabled) async {
    return _prefs.setBool(_keyBackgroundAudioEnabled, enabled);
  }

  /// Get system PiP enabled (default true — PiP follows user across apps).
  bool getSystemPipEnabled() {
    return _prefs.getBool(_keySystemPipEnabled) ??
        _prefs.getBool(_legacyKeySystemPipEnabled) ??
        true;
  }

  /// Save system PiP enabled.
  Future<bool> saveSystemPipEnabled(bool enabled) async {
    return _prefs.setBool(_keySystemPipEnabled, enabled);
  }

  // ==========================================================================
  // BANDWIDTH LIMITING
  // ==========================================================================

  static const _keyGlobalBandwidthLimit = 'settings_global_bandwidth_limit';

  /// Get global bandwidth limit in KB/s (0 = unlimited).
  int getGlobalBandwidthLimit() {
    return _prefs.getInt(_keyGlobalBandwidthLimit) ?? 0;
  }

  /// Save global bandwidth limit in KB/s (0 = unlimited).
  Future<bool> saveGlobalBandwidthLimit(int kbps) {
    return _prefs.setInt(_keyGlobalBandwidthLimit, kbps);
  }

  // ==================== WIFI-ONLY MODE ====================

  static const _keyWifiOnlyMode = 'settings_wifi_only_mode';

  /// Get WiFi-only mode (default false — allow any network).
  bool getWifiOnlyMode() {
    return _prefs.getBool(_keyWifiOnlyMode) ?? false;
  }

  /// Save WiFi-only mode.
  Future<bool> saveWifiOnlyMode(bool enabled) {
    return _prefs.setBool(_keyWifiOnlyMode, enabled);
  }

  // ==================== AUTO-THROTTLE ====================

  static const _keyAutoThrottle = 'settings_auto_throttle';

  /// Get auto-throttle enabled (default true — adjusts concurrency based on aggregate speed).
  bool getAutoThrottle() {
    return _prefs.getBool(_keyAutoThrottle) ?? true;
  }

  /// Save auto-throttle enabled.
  Future<bool> saveAutoThrottle(bool enabled) {
    return _prefs.setBool(_keyAutoThrottle, enabled);
  }

  // ==================== ADAPTIVE SEGMENTS ====================

  static const _keyAdaptiveSegments = 'settings_adaptive_segments';

  /// Get adaptive segments enabled (default true — auto-selects numSegments based on bandwidth).
  bool getAdaptiveSegments() {
    return _prefs.getBool(_keyAdaptiveSegments) ?? true;
  }

  /// Save adaptive segments enabled.
  Future<bool> saveAdaptiveSegments(bool enabled) {
    return _prefs.setBool(_keyAdaptiveSegments, enabled);
  }

  // ==========================================================================
  // SMART QUEUE
  // ==========================================================================

  static const _keyNetworkAwareQueueReorder =
      'settings_network_aware_queue_reorder';

  /// Get network-aware queue reorder (default false).
  bool getNetworkAwareQueueReorder() {
    return _prefs.getBool(_keyNetworkAwareQueueReorder) ?? false;
  }

  /// Save network-aware queue reorder.
  Future<bool> saveNetworkAwareQueueReorder(bool enabled) {
    return _prefs.setBool(_keyNetworkAwareQueueReorder, enabled);
  }

  // ==========================================================================
  // QUIET HOURS
  // ==========================================================================

  static const _keyQuietHoursEnabled = 'settings_quiet_hours_enabled';
  static const _keyQuietHoursStart = 'settings_quiet_hours_start';
  static const _keyQuietHoursEnd = 'settings_quiet_hours_end';
  static const _keyQuietHoursBandwidthKbps =
      'settings_quiet_hours_bandwidth_kbps';

  bool getQuietHoursEnabled() => _prefs.getBool(_keyQuietHoursEnabled) ?? false;
  Future<bool> saveQuietHoursEnabled(bool enabled) =>
      _prefs.setBool(_keyQuietHoursEnabled, enabled);

  int getQuietHoursStart() => _prefs.getInt(_keyQuietHoursStart) ?? 22;
  Future<bool> saveQuietHoursStart(int hour) =>
      _prefs.setInt(_keyQuietHoursStart, hour);

  int getQuietHoursEnd() => _prefs.getInt(_keyQuietHoursEnd) ?? 7;
  Future<bool> saveQuietHoursEnd(int hour) =>
      _prefs.setInt(_keyQuietHoursEnd, hour);

  int getQuietHoursBandwidthKbps() =>
      _prefs.getInt(_keyQuietHoursBandwidthKbps) ?? 1024;
  Future<bool> saveQuietHoursBandwidthKbps(int kbps) =>
      _prefs.setInt(_keyQuietHoursBandwidthKbps, kbps);

  // ==========================================================================
  // POST-DOWNLOAD ACTIONS
  // ==========================================================================

  static const _keyPostDownloadAction = 'settings_post_download_action';
  static const _keyPostDownloadTargetFolder =
      'settings_post_download_target_folder';

  /// Get the configured post-download action (default [PostDownloadAction.none]).
  PostDownloadAction getPostDownloadAction() {
    final stored = _prefs.getString(_keyPostDownloadAction);
    if (stored == null) return PostDownloadAction.none;
    return PostDownloadAction.values.firstWhere(
      (e) => e.name == stored,
      orElse: () => PostDownloadAction.none,
    );
  }

  /// Save the post-download action.
  Future<bool> savePostDownloadAction(PostDownloadAction action) {
    return _prefs.setString(_keyPostDownloadAction, action.name);
  }

  /// Get the target folder for move-based post-download actions.
  String getPostDownloadTargetFolder() {
    return _prefs.getString(_keyPostDownloadTargetFolder) ?? '';
  }

  /// Save the target folder for move-based post-download actions.
  Future<bool> savePostDownloadTargetFolder(String folder) {
    if (folder.isEmpty) {
      return _prefs.remove(_keyPostDownloadTargetFolder).then((_) => true);
    }
    return _prefs.setString(_keyPostDownloadTargetFolder, folder);
  }

  /// Clear all settings
  Future<bool> clearAll() async {
    await _prefs.remove(_keyDownloadPath);
    await _prefs.remove(_keyMaxConcurrentDownloads);
    await _prefs.remove(_keyThemeMode);
    await _prefs.remove(_keyAutoStartDownloads);
    await _prefs.remove(_keyAutoClipboardDetection);
    await _prefs.remove(_keyNotificationsEnabled);
    await _prefs.remove(_keyPreferredQuality);
    await _prefs.remove(_keyDefaultDownloadFileType);
    await _prefs.remove(_keyDefaultDownloadQualityIntent);
    await _prefs.remove(_keyDefaultDownloadQualityTarget);
    await _prefs.remove(_keyPlatformPreferences);
    // yt-dlp settings
    await _prefs.remove(_keyDownloadEngine);
    await _prefs.remove(_keyEnableApiFallback);
    await _prefs.remove(_keyAutoUpdateYtdlp);
    await _prefs.remove(_keyYtdlpTimeout);
    await _prefs.remove(_keyShowDownloadMethodBadge);
    // Format preferences
    await _prefs.remove(_keyVideoCodecPreference);
    await _prefs.remove(_keyAudioCodecPreference);
    await _prefs.remove(_keyContainerFormatPreference);
    await _prefs.remove(_keyFpsPreference);
    await _prefs.remove(_keyMaxResolution);
    // P0 Features
    await _prefs.remove(_keySubtitlesEnabled);
    await _prefs.remove(_keySubtitlesLanguages);
    await _prefs.remove(_keySubtitlesFormat);
    await _prefs.remove(_keyEmbedSubtitles);
    await _prefs.remove(_keyIncludeAutoSubs);
    await _prefs.remove(_keyWriteThumbnail);
    await _prefs.remove(_keyEmbedThumbnail);
    await _prefs.remove(_keyEmbedMetadata);
    await _prefs.remove(_keyEmbedChapters);
    await _prefs.remove(_keySponsorBlockEnabled);
    await _prefs.remove(_keySponsorBlockAction);
    await _prefs.remove(_keySponsorBlockCategories);
    // P1 Features
    await _prefs.remove(_keyForceRemux);
    // P2 Features
    await _prefs.remove(_keyTiktokRemoveWatermark);
    // P3 Features
    await _prefs.remove(_keyProxyUrl);
    await _prefs.remove(_keyGeoBypass);
    await _prefs.remove(_keyGeoBypassCountry);
    await _prefs.remove(_keyArchiveEnabled);
    await _prefs.remove(_keyDateAfter);
    await _prefs.remove(_keyDateBefore);
    await _prefs.remove(_keyMinDuration);
    await _prefs.remove(_keyMaxDuration);
    // Network Tuning
    await _prefs.remove(_keySocketTimeout);
    await _prefs.remove(_keyMaxRetries);
    await _prefs.remove(_keyHttpChunkSizeMb);
    // Filename Template
    await _prefs.remove(_keyFilenameTemplate);
    // Custom Postprocessor Args
    await _prefs.remove(_keyCustomPostprocessorArgs);
    // View mode & proxy list
    await _prefs.remove(_keyDownloadsViewMode);
    await _prefs.remove(_keyProxyList);
    await _prefs.remove(_keyAutoRetryEnabled);
    // Segments & bandwidth
    await _prefs.remove(_keyMaxSegments);
    await _prefs.remove(_keyBackgroundAudioEnabled);
    await _prefs.remove(_keySystemPipEnabled);
    await _prefs.remove(_legacyKeySystemPipEnabled);
    await _prefs.remove(_keyGlobalBandwidthLimit);
    await _prefs.remove(_keyWifiOnlyMode);
    await _prefs.remove(_keyAutoThrottle);
    await _prefs.remove(_keyAdaptiveSegments);
    await _prefs.remove(_keyNetworkAwareQueueReorder);
    // Quiet hours
    await _prefs.remove(_keyQuietHoursEnabled);
    await _prefs.remove(_keyQuietHoursStart);
    await _prefs.remove(_keyQuietHoursEnd);
    await _prefs.remove(_keyQuietHoursBandwidthKbps);
    // Post-download actions
    await _prefs.remove(_keyPostDownloadAction);
    await _prefs.remove(_keyPostDownloadTargetFolder);
    return true;
  }
}
