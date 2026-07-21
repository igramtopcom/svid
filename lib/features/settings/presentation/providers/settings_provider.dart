import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/brand_download_path_resolver.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/enums/audio_codec_preference.dart';
import '../../domain/enums/container_format_preference.dart';
import '../../domain/enums/download_engine.dart';
import '../../domain/enums/fps_preference.dart';
import '../../domain/enums/quality_preference.dart';
import '../../domain/enums/video_codec_preference.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../../downloads/domain/entities/post_download_action.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';

/// Settings state model
class SettingsState {
  final String downloadPath;
  final int maxConcurrentDownloads;
  final ThemeMode themeMode;
  final bool autoStartDownloads;
  final bool autoClipboardDetection;
  final bool notificationsEnabled;
  final QualityPreference preferredQuality;
  final DownloadFileType defaultDownloadFileType;
  final DownloadQualityIntent defaultDownloadQualityIntent;
  final PortableQualityTarget? defaultDownloadQualityTarget;

  // yt-dlp settings
  final DownloadEngine downloadEngine;
  final bool enableApiFallback;
  final bool autoUpdateYtdlp;
  final int ytdlpTimeout; // seconds
  final bool showDownloadMethodBadge;

  // Format preferences
  final VideoCodecPreference videoCodecPreference;
  final AudioCodecPreference audioCodecPreference;
  final ContainerFormatPreference containerFormatPreference;
  final FpsPreference fpsPreference;
  final int
  maxResolution; // 0 = unlimited, otherwise max height (e.g., 1080, 720)

  // === P0 Features: Subtitles ===
  final bool subtitlesEnabled;
  final List<String> subtitlesLanguages;
  final String subtitlesFormat; // srt, vtt, ass
  final bool embedSubtitles;
  final bool includeAutoSubs; // Include auto-translated subtitles

  // === P0 Features: Thumbnails ===
  final bool writeThumbnail;
  final bool embedThumbnail;

  // === P0 Features: Metadata ===
  final bool embedMetadata;
  final bool embedChapters;

  // === P0 Features: SponsorBlock ===
  final bool sponsorBlockEnabled;
  final String sponsorBlockAction; // skip, remove, chapter
  final List<String> sponsorBlockCategories;

  // === P1 Features: Remux ===
  final bool forceRemux; // Force remux to container format for compatibility

  // === P2 Features: Platform-specific ===
  final bool tiktokRemoveWatermark; // Remove TikTok watermark

  // === P3 Features: Power User ===
  // Geo-bypass & Proxy
  final String? proxyUrl; // Single proxy URL (null = disabled)
  final List<String>
  proxyList; // Multi-proxy list for rotation (empty = disabled)
  final bool geoBypass; // Enable geo-bypass
  final String? geoBypassCountry; // Country code for geo-bypass (null = auto)
  // Archive Mode
  final bool
  archiveEnabled; // Enable download archive (skip already downloaded)
  // Auto-Retry
  final bool
  autoRetryEnabled; // Auto-retry failed downloads with exponential backoff
  // Advanced Filters
  final String?
  dateAfter; // Download videos uploaded after this date (YYYYMMDD)
  final String?
  dateBefore; // Download videos uploaded before this date (YYYYMMDD)
  // Duration Filters
  final int? minDuration; // Minimum video duration in seconds (null = no limit)
  final int? maxDuration; // Maximum video duration in seconds (null = no limit)

  // === Network Tuning ===
  final int socketTimeout; // seconds, default 30, range 10-120
  final int maxRetries; // default 3, range 1-10
  final int httpChunkSizeMb; // MB, default 10, range 1-50
  final int
  maxSegments; // 1-16, default 4. Multi-segment parallel download for Rust engine

  // === Output Filename Template ===
  final String
  filenameTemplate; // yt-dlp -o template, default '%(title)s.%(ext)s'

  // === Custom Postprocessor Args ===
  final String customPostprocessorArgs; // FFmpeg args, default empty

  // === Downloads View Mode ===
  final String downloadsViewMode; // 'list' or 'grid'

  // === Post-Download Actions ===
  final PostDownloadAction
  postDownloadAction; // Action after download completes
  final String postDownloadTargetFolder; // Target folder for move actions

  // === Player Settings ===
  final bool
  backgroundAudioEnabled; // Keep audio playing when window loses focus

  /// System PiP follows the user across desktop apps by compacting the main
  /// window into an always-on-top player when the app loses focus.
  final bool systemPipEnabled;

  // === Bandwidth Limiting ===
  /// Global download speed cap in KB/s.  0 = unlimited.
  final int globalBandwidthLimit;

  // === Network Mode ===
  /// When true, downloads only start on WiFi connections.
  final bool wifiOnlyMode;

  // === Auto-Throttle ===
  /// When true, concurrency is reduced automatically when aggregate speed is low.
  final bool autoThrottle;

  // === Adaptive Segments ===
  /// When true, numSegments per download is selected automatically based on
  /// measured bandwidth (overrides the manual [maxSegments] picker).
  final bool adaptiveSegments;

  // === Smart Queue ===
  /// When true, pending downloads are reordered (smallest first) when
  /// aggregate bandwidth drops below 2 MB/s.
  final bool networkAwareQueueReorder;

  // === Quiet Hours ===
  /// When true, bandwidth is throttled to [quietHoursBandwidthKbps] during the
  /// configured quiet-hours window.
  final bool quietHoursEnabled;

  /// Start hour (0–23, local time) of the quiet-hours window (default 22 = 10 PM).
  final int quietHoursStart;

  /// End hour (0–23, local time) of the quiet-hours window (default 7 = 7 AM).
  final int quietHoursEnd;

  /// Bandwidth cap in KB/s applied during quiet hours (default 1024 = 1 MB/s).
  final int quietHoursBandwidthKbps;

  const SettingsState({
    required this.downloadPath,
    required this.maxConcurrentDownloads,
    required this.themeMode,
    required this.autoStartDownloads,
    required this.autoClipboardDetection,
    required this.notificationsEnabled,
    required this.preferredQuality,
    this.defaultDownloadFileType = DownloadFileType.video,
    this.defaultDownloadQualityIntent = DownloadQualityIntent.recommended,
    this.defaultDownloadQualityTarget,
    required this.downloadEngine,
    this.enableApiFallback = true,
    required this.autoUpdateYtdlp,
    required this.ytdlpTimeout,
    this.showDownloadMethodBadge = false,
    required this.videoCodecPreference,
    required this.audioCodecPreference,
    required this.containerFormatPreference,
    required this.fpsPreference,
    required this.maxResolution,
    // P0 Features
    required this.subtitlesEnabled,
    required this.subtitlesLanguages,
    required this.subtitlesFormat,
    required this.embedSubtitles,
    this.includeAutoSubs = false,
    required this.writeThumbnail,
    required this.embedThumbnail,
    required this.embedMetadata,
    required this.embedChapters,
    required this.sponsorBlockEnabled,
    required this.sponsorBlockAction,
    required this.sponsorBlockCategories,
    // P1 Features
    required this.forceRemux,
    // P2 Features
    required this.tiktokRemoveWatermark,
    // P3 Features
    this.proxyUrl,
    this.proxyList = const [],
    required this.geoBypass,
    this.geoBypassCountry,
    required this.archiveEnabled,
    this.autoRetryEnabled = true,
    this.dateAfter,
    this.dateBefore,
    this.minDuration,
    this.maxDuration,
    this.socketTimeout = 30,
    this.maxRetries = 3,
    this.httpChunkSizeMb = 10,
    this.maxSegments = 4,
    this.filenameTemplate = '%(title)s.%(ext)s',
    this.customPostprocessorArgs = '',
    this.downloadsViewMode = 'list',
    this.postDownloadAction = PostDownloadAction.none,
    this.postDownloadTargetFolder = '',
    this.backgroundAudioEnabled = true,
    this.systemPipEnabled = true,
    this.globalBandwidthLimit = 0,
    this.wifiOnlyMode = false,
    this.autoThrottle = true,
    this.adaptiveSegments = true,
    this.networkAwareQueueReorder = false,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
    this.quietHoursBandwidthKbps = 1024,
  });

  SettingsState copyWith({
    String? downloadPath,
    int? maxConcurrentDownloads,
    ThemeMode? themeMode,
    bool? autoStartDownloads,
    bool? autoClipboardDetection,
    bool? notificationsEnabled,
    QualityPreference? preferredQuality,
    DownloadFileType? defaultDownloadFileType,
    DownloadQualityIntent? defaultDownloadQualityIntent,
    PortableQualityTarget? Function()? defaultDownloadQualityTarget,
    DownloadEngine? downloadEngine,
    bool? enableApiFallback,
    bool? autoUpdateYtdlp,
    int? ytdlpTimeout,
    bool? showDownloadMethodBadge,
    VideoCodecPreference? videoCodecPreference,
    AudioCodecPreference? audioCodecPreference,
    ContainerFormatPreference? containerFormatPreference,
    FpsPreference? fpsPreference,
    int? maxResolution,
    // P0 Features
    bool? subtitlesEnabled,
    List<String>? subtitlesLanguages,
    String? subtitlesFormat,
    bool? embedSubtitles,
    bool? includeAutoSubs,
    bool? writeThumbnail,
    bool? embedThumbnail,
    bool? embedMetadata,
    bool? embedChapters,
    bool? sponsorBlockEnabled,
    String? sponsorBlockAction,
    List<String>? sponsorBlockCategories,
    // P1 Features
    bool? forceRemux,
    // P2 Features
    bool? tiktokRemoveWatermark,
    // P3 Features
    String? Function()? proxyUrl,
    List<String>? proxyList,
    bool? geoBypass,
    String? Function()? geoBypassCountry,
    bool? archiveEnabled,
    bool? autoRetryEnabled,
    String? Function()? dateAfter,
    String? Function()? dateBefore,
    int? Function()? minDuration,
    int? Function()? maxDuration,
    int? socketTimeout,
    int? maxRetries,
    int? httpChunkSizeMb,
    int? maxSegments,
    String? filenameTemplate,
    String? customPostprocessorArgs,
    String? downloadsViewMode,
    PostDownloadAction? postDownloadAction,
    String? postDownloadTargetFolder,
    bool? backgroundAudioEnabled,
    bool? systemPipEnabled,
    int? globalBandwidthLimit,
    bool? wifiOnlyMode,
    bool? autoThrottle,
    bool? adaptiveSegments,
    bool? networkAwareQueueReorder,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    int? quietHoursBandwidthKbps,
  }) {
    return SettingsState(
      downloadPath: downloadPath ?? this.downloadPath,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      themeMode: themeMode ?? this.themeMode,
      autoStartDownloads: autoStartDownloads ?? this.autoStartDownloads,
      autoClipboardDetection:
          autoClipboardDetection ?? this.autoClipboardDetection,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      defaultDownloadFileType:
          defaultDownloadFileType ?? this.defaultDownloadFileType,
      defaultDownloadQualityIntent:
          defaultDownloadQualityIntent ?? this.defaultDownloadQualityIntent,
      defaultDownloadQualityTarget:
          defaultDownloadQualityTarget != null
              ? defaultDownloadQualityTarget()
              : this.defaultDownloadQualityTarget,
      downloadEngine: downloadEngine ?? this.downloadEngine,
      enableApiFallback: enableApiFallback ?? this.enableApiFallback,
      autoUpdateYtdlp: autoUpdateYtdlp ?? this.autoUpdateYtdlp,
      ytdlpTimeout: ytdlpTimeout ?? this.ytdlpTimeout,
      showDownloadMethodBadge:
          showDownloadMethodBadge ?? this.showDownloadMethodBadge,
      videoCodecPreference: videoCodecPreference ?? this.videoCodecPreference,
      audioCodecPreference: audioCodecPreference ?? this.audioCodecPreference,
      containerFormatPreference:
          containerFormatPreference ?? this.containerFormatPreference,
      fpsPreference: fpsPreference ?? this.fpsPreference,
      maxResolution: maxResolution ?? this.maxResolution,
      // P0 Features
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      subtitlesLanguages: subtitlesLanguages ?? this.subtitlesLanguages,
      subtitlesFormat: subtitlesFormat ?? this.subtitlesFormat,
      embedSubtitles: embedSubtitles ?? this.embedSubtitles,
      includeAutoSubs: includeAutoSubs ?? this.includeAutoSubs,
      writeThumbnail: writeThumbnail ?? this.writeThumbnail,
      embedThumbnail: embedThumbnail ?? this.embedThumbnail,
      embedMetadata: embedMetadata ?? this.embedMetadata,
      embedChapters: embedChapters ?? this.embedChapters,
      sponsorBlockEnabled: sponsorBlockEnabled ?? this.sponsorBlockEnabled,
      sponsorBlockAction: sponsorBlockAction ?? this.sponsorBlockAction,
      sponsorBlockCategories:
          sponsorBlockCategories ?? this.sponsorBlockCategories,
      // P1 Features
      forceRemux: forceRemux ?? this.forceRemux,
      // P2 Features
      tiktokRemoveWatermark:
          tiktokRemoveWatermark ?? this.tiktokRemoveWatermark,
      // P3 Features
      proxyUrl: proxyUrl != null ? proxyUrl() : this.proxyUrl,
      proxyList: proxyList ?? this.proxyList,
      geoBypass: geoBypass ?? this.geoBypass,
      geoBypassCountry:
          geoBypassCountry != null ? geoBypassCountry() : this.geoBypassCountry,
      archiveEnabled: archiveEnabled ?? this.archiveEnabled,
      autoRetryEnabled: autoRetryEnabled ?? this.autoRetryEnabled,
      dateAfter: dateAfter != null ? dateAfter() : this.dateAfter,
      dateBefore: dateBefore != null ? dateBefore() : this.dateBefore,
      minDuration: minDuration != null ? minDuration() : this.minDuration,
      maxDuration: maxDuration != null ? maxDuration() : this.maxDuration,
      socketTimeout: socketTimeout ?? this.socketTimeout,
      maxRetries: maxRetries ?? this.maxRetries,
      httpChunkSizeMb: httpChunkSizeMb ?? this.httpChunkSizeMb,
      maxSegments: maxSegments ?? this.maxSegments,
      filenameTemplate: filenameTemplate ?? this.filenameTemplate,
      customPostprocessorArgs:
          customPostprocessorArgs ?? this.customPostprocessorArgs,
      downloadsViewMode: downloadsViewMode ?? this.downloadsViewMode,
      postDownloadAction: postDownloadAction ?? this.postDownloadAction,
      postDownloadTargetFolder:
          postDownloadTargetFolder ?? this.postDownloadTargetFolder,
      backgroundAudioEnabled:
          backgroundAudioEnabled ?? this.backgroundAudioEnabled,
      systemPipEnabled: systemPipEnabled ?? this.systemPipEnabled,
      globalBandwidthLimit: globalBandwidthLimit ?? this.globalBandwidthLimit,
      wifiOnlyMode: wifiOnlyMode ?? this.wifiOnlyMode,
      autoThrottle: autoThrottle ?? this.autoThrottle,
      adaptiveSegments: adaptiveSegments ?? this.adaptiveSegments,
      networkAwareQueueReorder:
          networkAwareQueueReorder ?? this.networkAwareQueueReorder,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      quietHoursBandwidthKbps:
          quietHoursBandwidthKbps ?? this.quietHoursBandwidthKbps,
    );
  }
}

/// Settings notifier with repository integration
class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsRepository _repository;

  SettingsNotifier(this._repository) : super(_defaultSettings()) {
    _init();
  }

  static SettingsState _defaultSettings() {
    return const SettingsState(
      downloadPath: '~/Downloads', // Will be replaced with actual path
      maxConcurrentDownloads: 3,
      themeMode: ThemeMode.system,
      autoStartDownloads: false,
      autoClipboardDetection: true,
      notificationsEnabled: true,
      preferredQuality: QualityPreference.auto,
      defaultDownloadFileType: DownloadFileType.video,
      defaultDownloadQualityIntent: DownloadQualityIntent.recommended,
      // yt-dlp defaults - PREFER YT-DLP, DISABLE API FALLBACK
      downloadEngine: DownloadEngine.ytdlpOnly,
      enableApiFallback: false,
      autoUpdateYtdlp: true,
      ytdlpTimeout: 30,
      showDownloadMethodBadge: true,
      // Format preferences - defaults for best compatibility
      videoCodecPreference: VideoCodecPreference.h264, // Most compatible
      audioCodecPreference: AudioCodecPreference.aac, // Most compatible
      containerFormatPreference:
          ContainerFormatPreference.mp4, // Most compatible
      fpsPreference: FpsPreference.auto,
      maxResolution: 0, // Unlimited
      // === P0 Features ===
      subtitlesEnabled: false,
      subtitlesLanguages: ['en'],
      subtitlesFormat: 'srt',
      embedSubtitles: true,
      writeThumbnail: false,
      embedThumbnail: true,
      embedMetadata: true,
      embedChapters: true,
      sponsorBlockEnabled: false,
      sponsorBlockAction: 'skip',
      sponsorBlockCategories: ['sponsor'],
      // === P1 Features ===
      forceRemux: false,
      // === P2 Features ===
      tiktokRemoveWatermark: true, // ON by default
      // === P3 Features ===
      proxyUrl: null,
      geoBypass: false,
      geoBypassCountry: null,
      archiveEnabled: false,
      autoRetryEnabled: true,
      dateAfter: null,
      dateBefore: null,
      minDuration: null,
      maxDuration: null,
    );
  }

  /// Initialize settings - load from storage and set download path
  Future<void> _init() async {
    try {
      // Try to load saved settings
      final savedSettings = await _repository.loadSettings();

      if (savedSettings != null) {
        appLogger.info('📥 Loaded settings from storage');
        state = savedSettings;
      } else {
        appLogger.info('📝 Using default settings');
      }

      // Validate saved download path still exists and is writable.
      // Only fall back to system Downloads if saved path is invalid.
      final savedPath = state.downloadPath;
      final savedDir = Directory(savedPath);

      if (savedPath == '~/Downloads' || !await savedDir.exists()) {
        // First launch OR saved path invalid → delegate to brand-aware
        // resolver. For Svid this is identical to the previous inline
        // getDownloadsDirectory() logic (no behavior change for existing
        // Svid users — see BrandDownloadPathResolver._svidPlatformDefault).
        // For VidCombo this auto-detects legacy ObjectBox folders
        // (~/Documents/VidCombo, ~/Downloads/VidCombo, OneDrive-redirected
        // variants) so the 1.6.x → 1.7.x rewrite does NOT silently strand
        // existing downloads behind a new path — the regression hit by
        // production feedback #78 ("All the music that i had download
        // before the new update 1.7.0 ... all gone or hid somewhere").
        // Resolver was added in commit e74a1af2 but never wired in until
        // production users surfaced the bug.
        final actualPath =
            await const BrandDownloadPathResolver().resolveFirstLaunchDefault();
        if (!mounted) return;
        state = state.copyWith(downloadPath: actualPath);
        await _repository.saveDownloadPath(actualPath);
        appLogger.info('📂 Download path resolved to: $actualPath');
      }
    } catch (e, stack) {
      appLogger.error('Failed to initialize settings', e, stack);
    }
  }

  /// Update download path
  Future<void> updateDownloadPath(String path) async {
    state = state.copyWith(downloadPath: path);
    await _repository.saveDownloadPath(path);
    appLogger.info('💾 Saved download path: $path');
  }

  /// Update max concurrent downloads
  Future<void> updateMaxConcurrentDownloads(int count) async {
    if (count < 1 || count > 10) return;
    state = state.copyWith(maxConcurrentDownloads: count);
    await _repository.saveMaxConcurrentDownloads(count);
    appLogger.info('💾 Saved max concurrent downloads: $count');
  }

  /// Update theme mode
  Future<void> updateThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _repository.saveThemeMode(mode);
    appLogger.info('💾 Saved theme mode: $mode');
  }

  /// Toggle auto start downloads
  Future<void> toggleAutoStartDownloads() async {
    final newValue = !state.autoStartDownloads;
    state = state.copyWith(autoStartDownloads: newValue);
    await _repository.saveAutoStartDownloads(newValue);
    appLogger.info('💾 Saved auto start downloads: $newValue');
  }

  /// Toggle auto clipboard detection
  Future<void> toggleAutoClipboardDetection() async {
    final newValue = !state.autoClipboardDetection;
    state = state.copyWith(autoClipboardDetection: newValue);
    await _repository.saveAutoClipboardDetection(newValue);
    appLogger.info('💾 Saved auto clipboard detection: $newValue');
  }

  /// Toggle notifications
  Future<void> toggleNotifications() async {
    final newValue = !state.notificationsEnabled;
    state = state.copyWith(notificationsEnabled: newValue);
    await _repository.saveNotificationsEnabled(newValue);
    appLogger.info('💾 Saved notifications enabled: $newValue');
  }

  /// Update preferred quality
  Future<void> updatePreferredQuality(QualityPreference preference) async {
    state = state.copyWith(preferredQuality: preference);
    await _repository.savePreferredQuality(preference);
    appLogger.info('💾 Saved preferred quality: ${preference.displayName}');
  }

  Future<void> updateDefaultDownloadSelection({
    required DownloadFileType fileType,
    required DownloadQualityIntent qualityIntent,
    PortableQualityTarget? qualityTarget,
  }) async {
    state = state.copyWith(
      defaultDownloadFileType: fileType,
      defaultDownloadQualityIntent: qualityIntent,
      defaultDownloadQualityTarget: () => qualityTarget,
    );
    await _repository.saveDefaultDownloadFileType(fileType);
    await _repository.saveDefaultDownloadQualityIntent(qualityIntent);
    await _repository.saveDefaultDownloadQualityTarget(qualityTarget);
    appLogger.info(
      '💾 Saved default download selection: ${fileType.name}/${qualityIntent.name}',
    );
  }

  /// Reset to defaults
  Future<void> resetToDefaults() async {
    await _repository.clearSettings();
    if (!mounted) return;
    state = _defaultSettings();
    await _init(); // Re-initialize download path
    appLogger.info('🔄 Reset settings to defaults');
  }

  // ==================== YT-DLP SETTINGS ====================

  /// Update download engine preference
  Future<void> updateDownloadEngine(DownloadEngine engine) async {
    state = state.copyWith(downloadEngine: engine);
    await _repository.saveDownloadEngine(engine);
    appLogger.info('💾 Saved download engine: ${engine.displayName}');
  }

  /// Toggle API fallback
  Future<void> toggleApiFallback() async {
    final newValue = !state.enableApiFallback;
    state = state.copyWith(enableApiFallback: newValue);
    await _repository.saveEnableApiFallback(newValue);
    appLogger.info('💾 Saved API fallback: $newValue');
  }

  /// Toggle auto-update yt-dlp
  Future<void> toggleAutoUpdateYtdlp() async {
    final newValue = !state.autoUpdateYtdlp;
    state = state.copyWith(autoUpdateYtdlp: newValue);
    await _repository.saveAutoUpdateYtdlp(newValue);
    appLogger.info('💾 Saved auto-update yt-dlp: $newValue');
  }

  /// Update yt-dlp timeout
  Future<void> updateYtdlpTimeout(int seconds) async {
    if (seconds < 5 || seconds > 120) return;
    state = state.copyWith(ytdlpTimeout: seconds);
    await _repository.saveYtdlpTimeout(seconds);
    appLogger.info('💾 Saved yt-dlp timeout: ${seconds}s');
  }

  /// Toggle download method badge
  Future<void> toggleDownloadMethodBadge() async {
    final newValue = !state.showDownloadMethodBadge;
    state = state.copyWith(showDownloadMethodBadge: newValue);
    await _repository.saveShowDownloadMethodBadge(newValue);
    appLogger.info('💾 Saved show download method badge: $newValue');
  }

  // ==================== FORMAT PREFERENCES ====================

  /// Update video codec preference
  Future<void> updateVideoCodecPreference(
    VideoCodecPreference preference,
  ) async {
    state = state.copyWith(videoCodecPreference: preference);
    await _repository.saveVideoCodecPreference(preference);
    appLogger.info(
      '💾 Saved video codec preference: ${preference.displayName}',
    );
  }

  /// Update audio codec preference
  Future<void> updateAudioCodecPreference(
    AudioCodecPreference preference,
  ) async {
    state = state.copyWith(audioCodecPreference: preference);
    await _repository.saveAudioCodecPreference(preference);
    appLogger.info(
      '💾 Saved audio codec preference: ${preference.displayName}',
    );
  }

  /// Update container format preference
  Future<void> updateContainerFormatPreference(
    ContainerFormatPreference preference,
  ) async {
    state = state.copyWith(containerFormatPreference: preference);
    await _repository.saveContainerFormatPreference(preference);
    appLogger.info(
      '💾 Saved container format preference: ${preference.displayName}',
    );
  }

  /// Update FPS preference
  Future<void> updateFpsPreference(FpsPreference preference) async {
    state = state.copyWith(fpsPreference: preference);
    await _repository.saveFpsPreference(preference);
    appLogger.info('💾 Saved FPS preference: ${preference.displayName}');
  }

  /// Update max resolution
  Future<void> updateMaxResolution(int resolution) async {
    state = state.copyWith(maxResolution: resolution);
    await _repository.saveMaxResolution(resolution);
    appLogger.info(
      '💾 Saved max resolution: ${resolution == 0 ? "Unlimited" : "${resolution}p"}',
    );
  }

  // ==================== P0 FEATURES ====================

  /// Toggle subtitles
  Future<void> toggleSubtitles() async {
    final newValue = !state.subtitlesEnabled;
    state = state.copyWith(subtitlesEnabled: newValue);
    await _repository.saveSubtitlesEnabled(newValue);
    appLogger.info('💾 Saved subtitles enabled: $newValue');
  }

  /// Update subtitles languages
  Future<void> updateSubtitlesLanguages(List<String> languages) async {
    state = state.copyWith(subtitlesLanguages: languages);
    await _repository.saveSubtitlesLanguages(languages);
    appLogger.info('💾 Saved subtitles languages: $languages');
  }

  /// Update subtitles format
  Future<void> updateSubtitlesFormat(String format) async {
    state = state.copyWith(subtitlesFormat: format);
    await _repository.saveSubtitlesFormat(format);
    appLogger.info('💾 Saved subtitles format: $format');
  }

  /// Toggle include auto-translated subtitles
  Future<void> toggleIncludeAutoSubs() async {
    final newValue = !state.includeAutoSubs;
    state = state.copyWith(includeAutoSubs: newValue);
    await _repository.saveIncludeAutoSubs(newValue);
    appLogger.info('💾 Saved include auto subs: $newValue');
  }

  /// Toggle embed subtitles
  Future<void> toggleEmbedSubtitles() async {
    final newValue = !state.embedSubtitles;
    state = state.copyWith(embedSubtitles: newValue);
    await _repository.saveEmbedSubtitles(newValue);
    appLogger.info('💾 Saved embed subtitles: $newValue');
  }

  /// Toggle write thumbnail
  Future<void> toggleWriteThumbnail() async {
    final newValue = !state.writeThumbnail;
    state = state.copyWith(writeThumbnail: newValue);
    await _repository.saveWriteThumbnail(newValue);
    appLogger.info('💾 Saved write thumbnail: $newValue');
  }

  /// Toggle embed thumbnail
  Future<void> toggleEmbedThumbnail() async {
    final newValue = !state.embedThumbnail;
    state = state.copyWith(embedThumbnail: newValue);
    await _repository.saveEmbedThumbnail(newValue);
    appLogger.info('💾 Saved embed thumbnail: $newValue');
  }

  /// Toggle embed metadata
  Future<void> toggleEmbedMetadata() async {
    final newValue = !state.embedMetadata;
    state = state.copyWith(embedMetadata: newValue);
    await _repository.saveEmbedMetadata(newValue);
    appLogger.info('💾 Saved embed metadata: $newValue');
  }

  /// Toggle embed chapters
  Future<void> toggleEmbedChapters() async {
    final newValue = !state.embedChapters;
    state = state.copyWith(embedChapters: newValue);
    await _repository.saveEmbedChapters(newValue);
    appLogger.info('💾 Saved embed chapters: $newValue');
  }

  /// Toggle SponsorBlock
  Future<void> toggleSponsorBlock() async {
    final newValue = !state.sponsorBlockEnabled;
    state = state.copyWith(sponsorBlockEnabled: newValue);
    await _repository.saveSponsorBlockEnabled(newValue);
    appLogger.info('💾 Saved SponsorBlock enabled: $newValue');
  }

  /// Update SponsorBlock action
  Future<void> updateSponsorBlockAction(String action) async {
    state = state.copyWith(sponsorBlockAction: action);
    await _repository.saveSponsorBlockAction(action);
    appLogger.info('💾 Saved SponsorBlock action: $action');
  }

  /// Update SponsorBlock categories
  Future<void> updateSponsorBlockCategories(List<String> categories) async {
    state = state.copyWith(sponsorBlockCategories: categories);
    await _repository.saveSponsorBlockCategories(categories);
    appLogger.info('💾 Saved SponsorBlock categories: $categories');
  }

  // ==================== P1 FEATURES ====================

  /// Toggle force remux
  Future<void> toggleForceRemux() async {
    final newValue = !state.forceRemux;
    state = state.copyWith(forceRemux: newValue);
    await _repository.saveForceRemux(newValue);
    appLogger.info('💾 Saved force remux: $newValue');
  }

  // ==================== P2 FEATURES ====================

  /// Toggle TikTok remove watermark
  Future<void> toggleTiktokRemoveWatermark() async {
    final newValue = !state.tiktokRemoveWatermark;
    state = state.copyWith(tiktokRemoveWatermark: newValue);
    await _repository.saveTiktokRemoveWatermark(newValue);
    appLogger.info('💾 Saved TikTok remove watermark: $newValue');
  }

  // ==================== P3 FEATURES ====================

  /// Update proxy URL (null to disable)
  Future<void> updateProxyUrl(String? url) async {
    state = state.copyWith(proxyUrl: () => url);
    await _repository.saveProxyUrl(url);
    appLogger.info('💾 Saved proxy URL: ${url ?? "disabled"}');
  }

  /// Update proxy list (empty list = disabled)
  Future<void> updateProxyList(List<String> proxies) async {
    state = state.copyWith(proxyList: proxies);
    await _repository.saveProxyList(proxies);
    appLogger.info('💾 Saved proxy list: ${proxies.length} entries');
  }

  /// Toggle geo-bypass
  Future<void> toggleGeoBypass() async {
    final newValue = !state.geoBypass;
    state = state.copyWith(geoBypass: newValue);
    await _repository.saveGeoBypass(newValue);
    appLogger.info('💾 Saved geo-bypass: $newValue');
  }

  /// Update geo-bypass country (null for auto)
  Future<void> updateGeoBypassCountry(String? country) async {
    state = state.copyWith(geoBypassCountry: () => country);
    await _repository.saveGeoBypassCountry(country);
    appLogger.info('💾 Saved geo-bypass country: ${country ?? "auto"}');
  }

  /// Toggle archive mode
  Future<void> toggleArchiveEnabled() async {
    final newValue = !state.archiveEnabled;
    state = state.copyWith(archiveEnabled: newValue);
    await _repository.saveArchiveEnabled(newValue);
    appLogger.info('💾 Saved archive enabled: $newValue');
  }

  /// Toggle auto-retry for failed downloads
  Future<void> toggleAutoRetryEnabled() async {
    final newValue = !state.autoRetryEnabled;
    state = state.copyWith(autoRetryEnabled: newValue);
    await _repository.saveAutoRetryEnabled(newValue);
    appLogger.info('💾 Saved auto-retry enabled: $newValue');
  }

  /// Update date after filter (YYYYMMDD format, null to disable)
  Future<void> updateDateAfter(String? date) async {
    state = state.copyWith(dateAfter: () => date);
    await _repository.saveDateAfter(date);
    appLogger.info('💾 Saved date after: ${date ?? "disabled"}');
  }

  /// Update date before filter (YYYYMMDD format, null to disable)
  Future<void> updateDateBefore(String? date) async {
    state = state.copyWith(dateBefore: () => date);
    await _repository.saveDateBefore(date);
    appLogger.info('💾 Saved date before: ${date ?? "disabled"}');
  }

  /// Update minimum duration filter (seconds, null to disable)
  Future<void> updateMinDuration(int? seconds) async {
    state = state.copyWith(minDuration: () => seconds);
    await _repository.saveMinDuration(seconds);
    appLogger.info('💾 Saved min duration: ${seconds ?? "disabled"}');
  }

  /// Update maximum duration filter (seconds, null to disable)
  Future<void> updateMaxDuration(int? seconds) async {
    state = state.copyWith(maxDuration: () => seconds);
    await _repository.saveMaxDuration(seconds);
    appLogger.info('💾 Saved max duration: ${seconds ?? "disabled"}');
  }

  // ==================== NETWORK TUNING ====================

  /// Update socket timeout (seconds)
  Future<void> updateSocketTimeout(int seconds) async {
    if (seconds < 10 || seconds > 120) return;
    state = state.copyWith(socketTimeout: seconds);
    await _repository.saveSocketTimeout(seconds);
    appLogger.info('💾 Saved socket timeout: ${seconds}s');
  }

  /// Update max retries
  Future<void> updateMaxRetries(int retries) async {
    if (retries < 1 || retries > 10) return;
    state = state.copyWith(maxRetries: retries);
    await _repository.saveMaxRetries(retries);
    appLogger.info('💾 Saved max retries: $retries');
  }

  /// Update HTTP chunk size (MB)
  Future<void> updateHttpChunkSizeMb(int sizeMb) async {
    if (sizeMb < 1 || sizeMb > 50) return;
    state = state.copyWith(httpChunkSizeMb: sizeMb);
    await _repository.saveHttpChunkSizeMb(sizeMb);
    appLogger.info('💾 Saved HTTP chunk size: ${sizeMb}MB');
  }

  // ==================== OUTPUT FILENAME TEMPLATE ====================

  /// Update output filename template
  Future<void> updateFilenameTemplate(String template) async {
    state = state.copyWith(filenameTemplate: template);
    await _repository.saveFilenameTemplate(template);
    appLogger.info('💾 Saved filename template: $template');
  }

  // ==================== CUSTOM POSTPROCESSOR ARGS ====================

  /// Update custom FFmpeg postprocessor args
  Future<void> updateCustomPostprocessorArgs(String args) async {
    state = state.copyWith(customPostprocessorArgs: args);
    await _repository.saveCustomPostprocessorArgs(args);
    appLogger.info('💾 Saved custom postprocessor args: $args');
  }

  // ==================== DOWNLOADS VIEW MODE ====================

  /// Update downloads view mode ('list' or 'grid')
  Future<void> updateDownloadsViewMode(String mode) async {
    state = state.copyWith(downloadsViewMode: mode);
    await _repository.saveDownloadsViewMode(mode);
  }

  // ==================== POST-DOWNLOAD ACTIONS ====================

  /// Update the action to perform after a download completes.
  Future<void> updatePostDownloadAction(PostDownloadAction action) async {
    state = state.copyWith(postDownloadAction: action);
    await _repository.savePostDownloadAction(action);
    appLogger.info('💾 Saved post-download action: ${action.name}');
  }

  /// Update the target folder for move-based post-download actions.
  Future<void> updatePostDownloadTargetFolder(String folder) async {
    state = state.copyWith(postDownloadTargetFolder: folder);
    await _repository.savePostDownloadTargetFolder(folder);
    appLogger.info('💾 Saved post-download target folder: $folder');
  }

  // ==================== PLAYER SETTINGS ====================

  /// Toggle background audio (audio players keep playing when window loses focus)
  Future<void> toggleBackgroundAudioEnabled() async {
    final newValue = !state.backgroundAudioEnabled;
    state = state.copyWith(backgroundAudioEnabled: newValue);
    await _repository.saveBackgroundAudioEnabled(newValue);
    appLogger.info('💾 Saved background audio enabled: $newValue');
  }

  /// V2 reconcile: toggle macOS system PiP integration.
  Future<void> toggleSystemPipEnabled() async {
    final newValue = !state.systemPipEnabled;
    state = state.copyWith(systemPipEnabled: newValue);
    await _repository.saveSystemPipEnabled(newValue);
    appLogger.info('💾 Saved system PiP enabled: $newValue');
  }

  /// Set global bandwidth limit (0 = unlimited, >0 = KB/s cap).
  Future<void> updateGlobalBandwidthLimit(int kbps) async {
    state = state.copyWith(globalBandwidthLimit: kbps);
    await _repository.saveGlobalBandwidthLimit(kbps);
    appLogger.info(
      '💾 Saved global bandwidth limit: ${kbps == 0 ? "unlimited" : "$kbps KB/s"}',
    );
  }

  /// Toggle WiFi-only download mode.
  Future<void> updateWifiOnlyMode(bool enabled) async {
    state = state.copyWith(wifiOnlyMode: enabled);
    await _repository.saveWifiOnlyMode(enabled);
    appLogger.info('💾 Saved WiFi-only mode: $enabled');
  }

  /// Toggle auto-throttle mode.
  Future<void> updateAutoThrottle(bool enabled) async {
    state = state.copyWith(autoThrottle: enabled);
    await _repository.saveAutoThrottle(enabled);
    appLogger.info('💾 Saved auto-throttle: $enabled');
  }

  /// Toggle adaptive segments mode.
  Future<void> updateAdaptiveSegments(bool enabled) async {
    state = state.copyWith(adaptiveSegments: enabled);
    await _repository.saveAdaptiveSegments(enabled);
    appLogger.info('💾 Saved adaptive segments: $enabled');
  }

  /// Toggle network-aware queue reorder.
  Future<void> updateNetworkAwareQueueReorder(bool enabled) async {
    state = state.copyWith(networkAwareQueueReorder: enabled);
    await _repository.saveNetworkAwareQueueReorder(enabled);
    appLogger.info('💾 Saved network-aware queue reorder: $enabled');
  }

  /// Toggle quiet hours.
  Future<void> updateQuietHoursEnabled(bool enabled) async {
    state = state.copyWith(quietHoursEnabled: enabled);
    await _repository.saveQuietHoursEnabled(enabled);
    appLogger.info('💾 Saved quiet hours enabled: $enabled');
  }

  /// Set quiet hours start hour (0–23).
  Future<void> updateQuietHoursStart(int hour) async {
    state = state.copyWith(quietHoursStart: hour.clamp(0, 23));
    await _repository.saveQuietHoursStart(hour.clamp(0, 23));
    appLogger.info('💾 Saved quiet hours start: $hour');
  }

  /// Set quiet hours end hour (0–23).
  Future<void> updateQuietHoursEnd(int hour) async {
    state = state.copyWith(quietHoursEnd: hour.clamp(0, 23));
    await _repository.saveQuietHoursEnd(hour.clamp(0, 23));
    appLogger.info('💾 Saved quiet hours end: $hour');
  }

  /// Set quiet hours bandwidth cap in KB/s.
  Future<void> updateQuietHoursBandwidthKbps(int kbps) async {
    state = state.copyWith(quietHoursBandwidthKbps: kbps.clamp(64, 102400));
    await _repository.saveQuietHoursBandwidthKbps(kbps.clamp(64, 102400));
    appLogger.info('💾 Saved quiet hours bandwidth: $kbps KB/s');
  }
}

// ==================== PROVIDERS ====================

/// SharedPreferences provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Settings local datasource provider
final settingsLocalDatasourceProvider = Provider<SettingsLocalDatasource>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsLocalDatasource(prefs);
});

/// Settings repository provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final datasource = ref.watch(settingsLocalDatasourceProvider);
  return SettingsRepositoryImpl(datasource);
});

/// Settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    final repository = ref.watch(settingsRepositoryProvider);
    return SettingsNotifier(repository);
  },
);

/// Theme mode provider (derived from settings)
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(settingsProvider).themeMode;
});

/// Download path provider (derived from settings)
final downloadPathProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).downloadPath;
});

/// Max concurrent downloads provider (derived from settings)
final maxConcurrentDownloadsProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).maxConcurrentDownloads;
});

// ==================== YT-DLP SETTINGS PROVIDERS ====================

/// Download engine provider (derived from settings)
final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  return ref.watch(settingsProvider).downloadEngine;
});

/// API fallback enabled provider (derived from settings)
final enableApiFallbackProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).enableApiFallback;
});

/// Auto-update yt-dlp provider (derived from settings)
final autoUpdateYtdlpProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).autoUpdateYtdlp;
});

/// yt-dlp timeout provider (derived from settings)
final ytdlpTimeoutProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).ytdlpTimeout;
});

/// Show download method badge provider (derived from settings)
final showDownloadMethodBadgeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).showDownloadMethodBadge;
});

// ==================== FORMAT PREFERENCES PROVIDERS ====================

/// Video codec preference provider (derived from settings)
final videoCodecPreferenceProvider = Provider<VideoCodecPreference>((ref) {
  return ref.watch(settingsProvider).videoCodecPreference;
});

/// Audio codec preference provider (derived from settings)
final audioCodecPreferenceProvider = Provider<AudioCodecPreference>((ref) {
  return ref.watch(settingsProvider).audioCodecPreference;
});

/// Container format preference provider (derived from settings)
final containerFormatPreferenceProvider = Provider<ContainerFormatPreference>((
  ref,
) {
  return ref.watch(settingsProvider).containerFormatPreference;
});

/// FPS preference provider (derived from settings)
final fpsPreferenceProvider = Provider<FpsPreference>((ref) {
  return ref.watch(settingsProvider).fpsPreference;
});

/// Max resolution provider (derived from settings)
final maxResolutionProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).maxResolution;
});
