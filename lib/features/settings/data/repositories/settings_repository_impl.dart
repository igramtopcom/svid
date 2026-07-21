import 'package:flutter/material.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';
import 'package:svid/features/settings/domain/enums/fps_preference.dart';
import 'package:svid/features/settings/domain/enums/quality_preference.dart';
import 'package:svid/features/settings/domain/enums/video_codec_preference.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../presentation/providers/settings_provider.dart';
import '../datasources/settings_local_datasource.dart';
import '../../../downloads/domain/entities/post_download_action.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';

/// Implementation of SettingsRepository
/// Handles settings persistence using local datasource
class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDatasource _localDatasource;

  SettingsRepositoryImpl(this._localDatasource);

  @override
  Future<SettingsState?> loadSettings() async {
    try {
      final downloadPath = _localDatasource.getDownloadPath();
      final maxConcurrentDownloads =
          _localDatasource.getMaxConcurrentDownloads();
      final themeMode = _localDatasource.getThemeMode();
      final autoStartDownloads = _localDatasource.getAutoStartDownloads();
      final autoClipboardDetection =
          _localDatasource.getAutoClipboardDetection();
      final notificationsEnabled = _localDatasource.getNotificationsEnabled();
      final preferredQuality = _localDatasource.getPreferredQuality();
      final defaultDownloadFileType =
          _localDatasource.getDefaultDownloadFileType() ??
          _legacyFileType(preferredQuality);
      final defaultDownloadQualityIntent =
          _localDatasource.getDefaultDownloadQualityIntent() ??
          _legacyQualityIntent(preferredQuality);
      final defaultDownloadQualityTarget =
          _localDatasource.getDefaultDownloadQualityTarget() ??
          _legacyQualityTarget(preferredQuality);
      // yt-dlp settings
      final downloadEngine = _localDatasource.getDownloadEngine();
      final enableApiFallback = _localDatasource.getEnableApiFallback();
      final autoUpdateYtdlp = _localDatasource.getAutoUpdateYtdlp();
      final ytdlpTimeout = _localDatasource.getYtdlpTimeout();
      final showDownloadMethodBadge =
          _localDatasource.getShowDownloadMethodBadge();
      // Format preferences
      final videoCodecPreference = _localDatasource.getVideoCodecPreference();
      final audioCodecPreference = _localDatasource.getAudioCodecPreference();
      final containerFormatPreference =
          _localDatasource.getContainerFormatPreference();
      final fpsPreference = _localDatasource.getFpsPreference();
      final maxResolution = _localDatasource.getMaxResolution();
      // P0 Features
      final subtitlesEnabled = _localDatasource.getSubtitlesEnabled();
      final subtitlesLanguages = _localDatasource.getSubtitlesLanguages();
      final subtitlesFormat = _localDatasource.getSubtitlesFormat();
      final embedSubtitles = _localDatasource.getEmbedSubtitles();
      final includeAutoSubs = _localDatasource.getIncludeAutoSubs();
      final writeThumbnail = _localDatasource.getWriteThumbnail();
      final embedThumbnail = _localDatasource.getEmbedThumbnail();
      final embedMetadata = _localDatasource.getEmbedMetadata();
      final embedChapters = _localDatasource.getEmbedChapters();
      final sponsorBlockEnabled = _localDatasource.getSponsorBlockEnabled();
      final sponsorBlockAction = _localDatasource.getSponsorBlockAction();
      final sponsorBlockCategories =
          _localDatasource.getSponsorBlockCategories();
      // P1 Features
      final forceRemux = _localDatasource.getForceRemux();
      // P2 Features
      final tiktokRemoveWatermark = _localDatasource.getTiktokRemoveWatermark();
      // P3 Features
      final proxyUrl = _localDatasource.getProxyUrl();
      final proxyList = _localDatasource.getProxyList();
      final geoBypass = _localDatasource.getGeoBypass();
      final geoBypassCountry = _localDatasource.getGeoBypassCountry();
      final archiveEnabled = _localDatasource.getArchiveEnabled();
      final autoRetryEnabled = _localDatasource.getAutoRetryEnabled();
      final dateAfter = _localDatasource.getDateAfter();
      final dateBefore = _localDatasource.getDateBefore();
      final minDuration = _localDatasource.getMinDuration();
      final maxDuration = _localDatasource.getMaxDuration();
      // Network Tuning
      final socketTimeout = _localDatasource.getSocketTimeout();
      final maxRetries = _localDatasource.getMaxRetries();
      final httpChunkSizeMb = _localDatasource.getHttpChunkSizeMb();
      final maxSegments = _localDatasource.getMaxSegments();
      // Filename Template
      final filenameTemplate = _localDatasource.getFilenameTemplate();
      // Custom Postprocessor Args
      final customPostprocessorArgs =
          _localDatasource.getCustomPostprocessorArgs();
      // Downloads view mode
      final downloadsViewMode = _localDatasource.getDownloadsViewMode();
      // Post-download actions
      final postDownloadAction = _localDatasource.getPostDownloadAction();
      final postDownloadTargetFolder =
          _localDatasource.getPostDownloadTargetFolder();
      // Player settings
      final backgroundAudioEnabled =
          _localDatasource.getBackgroundAudioEnabled();
      final systemPipEnabled = _localDatasource.getSystemPipEnabled();
      // Bandwidth limiting
      final globalBandwidthLimit = _localDatasource.getGlobalBandwidthLimit();
      // WiFi-only mode
      final wifiOnlyMode = _localDatasource.getWifiOnlyMode();
      // Auto-throttle
      final autoThrottle = _localDatasource.getAutoThrottle();
      // Adaptive segments
      final adaptiveSegments = _localDatasource.getAdaptiveSegments();
      // Smart queue
      final networkAwareQueueReorder =
          _localDatasource.getNetworkAwareQueueReorder();
      // Quiet hours
      final quietHoursEnabled = _localDatasource.getQuietHoursEnabled();
      final quietHoursStart = _localDatasource.getQuietHoursStart();
      final quietHoursEnd = _localDatasource.getQuietHoursEnd();
      final quietHoursBandwidthKbps =
          _localDatasource.getQuietHoursBandwidthKbps();

      // Only return if at least one setting is stored
      if (downloadPath == null && maxConcurrentDownloads == null) {
        return null; // No settings stored yet
      }

      return SettingsState(
        downloadPath: downloadPath ?? '~/Downloads',
        maxConcurrentDownloads: maxConcurrentDownloads ?? 3,
        themeMode: themeMode,
        autoStartDownloads: autoStartDownloads,
        autoClipboardDetection: autoClipboardDetection,
        notificationsEnabled: notificationsEnabled,
        preferredQuality: preferredQuality,
        defaultDownloadFileType: defaultDownloadFileType,
        defaultDownloadQualityIntent: defaultDownloadQualityIntent,
        defaultDownloadQualityTarget: defaultDownloadQualityTarget,
        downloadEngine: downloadEngine,
        enableApiFallback: enableApiFallback,
        autoUpdateYtdlp: autoUpdateYtdlp,
        ytdlpTimeout: ytdlpTimeout,
        showDownloadMethodBadge: showDownloadMethodBadge,
        videoCodecPreference: videoCodecPreference,
        audioCodecPreference: audioCodecPreference,
        containerFormatPreference: containerFormatPreference,
        fpsPreference: fpsPreference,
        maxResolution: maxResolution,
        // P0 Features
        subtitlesEnabled: subtitlesEnabled,
        subtitlesLanguages: subtitlesLanguages,
        subtitlesFormat: subtitlesFormat,
        embedSubtitles: embedSubtitles,
        includeAutoSubs: includeAutoSubs,
        writeThumbnail: writeThumbnail,
        embedThumbnail: embedThumbnail,
        embedMetadata: embedMetadata,
        embedChapters: embedChapters,
        sponsorBlockEnabled: sponsorBlockEnabled,
        sponsorBlockAction: sponsorBlockAction,
        sponsorBlockCategories: sponsorBlockCategories,
        // P1 Features
        forceRemux: forceRemux,
        // P2 Features
        tiktokRemoveWatermark: tiktokRemoveWatermark,
        // P3 Features
        proxyUrl: proxyUrl,
        proxyList: proxyList,
        geoBypass: geoBypass,
        geoBypassCountry: geoBypassCountry,
        archiveEnabled: archiveEnabled,
        autoRetryEnabled: autoRetryEnabled,
        dateAfter: dateAfter,
        dateBefore: dateBefore,
        minDuration: minDuration,
        maxDuration: maxDuration,
        socketTimeout: socketTimeout,
        maxRetries: maxRetries,
        httpChunkSizeMb: httpChunkSizeMb,
        maxSegments: maxSegments,
        filenameTemplate: filenameTemplate,
        customPostprocessorArgs: customPostprocessorArgs,
        downloadsViewMode: downloadsViewMode,
        postDownloadAction: postDownloadAction,
        postDownloadTargetFolder: postDownloadTargetFolder,
        backgroundAudioEnabled: backgroundAudioEnabled,
        systemPipEnabled: systemPipEnabled,
        globalBandwidthLimit: globalBandwidthLimit,
        wifiOnlyMode: wifiOnlyMode,
        autoThrottle: autoThrottle,
        adaptiveSegments: adaptiveSegments,
        networkAwareQueueReorder: networkAwareQueueReorder,
        quietHoursEnabled: quietHoursEnabled,
        quietHoursStart: quietHoursStart,
        quietHoursEnd: quietHoursEnd,
        quietHoursBandwidthKbps: quietHoursBandwidthKbps,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> saveSettings(SettingsState settings) async {
    try {
      await _localDatasource.saveDownloadPath(settings.downloadPath);
      await _localDatasource.saveMaxConcurrentDownloads(
        settings.maxConcurrentDownloads,
      );
      await _localDatasource.saveThemeMode(settings.themeMode);
      await _localDatasource.saveAutoStartDownloads(
        settings.autoStartDownloads,
      );
      await _localDatasource.saveAutoClipboardDetection(
        settings.autoClipboardDetection,
      );
      await _localDatasource.saveNotificationsEnabled(
        settings.notificationsEnabled,
      );
      await _localDatasource.savePreferredQuality(settings.preferredQuality);
      await _localDatasource.saveDefaultDownloadFileType(
        settings.defaultDownloadFileType,
      );
      await _localDatasource.saveDefaultDownloadQualityIntent(
        settings.defaultDownloadQualityIntent,
      );
      await _localDatasource.saveDefaultDownloadQualityTarget(
        settings.defaultDownloadQualityTarget,
      );
      // yt-dlp settings
      await _localDatasource.saveDownloadEngine(settings.downloadEngine);
      await _localDatasource.saveEnableApiFallback(settings.enableApiFallback);
      await _localDatasource.saveAutoUpdateYtdlp(settings.autoUpdateYtdlp);
      await _localDatasource.saveYtdlpTimeout(settings.ytdlpTimeout);
      await _localDatasource.saveShowDownloadMethodBadge(
        settings.showDownloadMethodBadge,
      );
      // Format preferences
      await _localDatasource.saveVideoCodecPreference(
        settings.videoCodecPreference,
      );
      await _localDatasource.saveAudioCodecPreference(
        settings.audioCodecPreference,
      );
      await _localDatasource.saveContainerFormatPreference(
        settings.containerFormatPreference,
      );
      await _localDatasource.saveFpsPreference(settings.fpsPreference);
      await _localDatasource.saveMaxResolution(settings.maxResolution);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> saveDownloadPath(String path) async {
    return _localDatasource.saveDownloadPath(path);
  }

  @override
  Future<bool> saveMaxConcurrentDownloads(int count) async {
    return _localDatasource.saveMaxConcurrentDownloads(count);
  }

  @override
  Future<bool> saveThemeMode(ThemeMode mode) async {
    return _localDatasource.saveThemeMode(mode);
  }

  @override
  Future<bool> saveAutoStartDownloads(bool enabled) async {
    return _localDatasource.saveAutoStartDownloads(enabled);
  }

  @override
  Future<bool> saveAutoClipboardDetection(bool enabled) async {
    return _localDatasource.saveAutoClipboardDetection(enabled);
  }

  @override
  Future<bool> saveNotificationsEnabled(bool enabled) async {
    return _localDatasource.saveNotificationsEnabled(enabled);
  }

  @override
  Future<bool> savePreferredQuality(QualityPreference preference) async {
    return _localDatasource.savePreferredQuality(preference);
  }

  @override
  Future<bool> saveDefaultDownloadFileType(DownloadFileType fileType) async {
    return _localDatasource.saveDefaultDownloadFileType(fileType);
  }

  @override
  Future<bool> saveDefaultDownloadQualityIntent(
    DownloadQualityIntent qualityIntent,
  ) async {
    return _localDatasource.saveDefaultDownloadQualityIntent(qualityIntent);
  }

  @override
  Future<bool> saveDefaultDownloadQualityTarget(
    PortableQualityTarget? qualityTarget,
  ) async {
    return _localDatasource.saveDefaultDownloadQualityTarget(qualityTarget);
  }

  // ==================== YT-DLP SETTINGS ====================

  @override
  Future<bool> saveDownloadEngine(DownloadEngine engine) async {
    return _localDatasource.saveDownloadEngine(engine);
  }

  @override
  Future<bool> saveEnableApiFallback(bool enabled) async {
    return _localDatasource.saveEnableApiFallback(enabled);
  }

  @override
  Future<bool> saveAutoUpdateYtdlp(bool enabled) async {
    return _localDatasource.saveAutoUpdateYtdlp(enabled);
  }

  @override
  Future<bool> saveYtdlpTimeout(int seconds) async {
    return _localDatasource.saveYtdlpTimeout(seconds);
  }

  @override
  Future<bool> saveShowDownloadMethodBadge(bool show) async {
    return _localDatasource.saveShowDownloadMethodBadge(show);
  }

  // ==================== FORMAT PREFERENCES ====================

  @override
  Future<bool> saveVideoCodecPreference(VideoCodecPreference preference) async {
    return _localDatasource.saveVideoCodecPreference(preference);
  }

  @override
  Future<bool> saveAudioCodecPreference(AudioCodecPreference preference) async {
    return _localDatasource.saveAudioCodecPreference(preference);
  }

  @override
  Future<bool> saveContainerFormatPreference(
    ContainerFormatPreference preference,
  ) async {
    return _localDatasource.saveContainerFormatPreference(preference);
  }

  @override
  Future<bool> saveFpsPreference(FpsPreference preference) async {
    return _localDatasource.saveFpsPreference(preference);
  }

  @override
  Future<bool> saveMaxResolution(int resolution) async {
    return _localDatasource.saveMaxResolution(resolution);
  }

  // ==================== P0 FEATURES ====================

  @override
  Future<bool> saveSubtitlesEnabled(bool enabled) async {
    return _localDatasource.saveSubtitlesEnabled(enabled);
  }

  @override
  Future<bool> saveSubtitlesLanguages(List<String> languages) async {
    return _localDatasource.saveSubtitlesLanguages(languages);
  }

  @override
  Future<bool> saveSubtitlesFormat(String format) async {
    return _localDatasource.saveSubtitlesFormat(format);
  }

  @override
  Future<bool> saveEmbedSubtitles(bool enabled) async {
    return _localDatasource.saveEmbedSubtitles(enabled);
  }

  @override
  Future<bool> saveIncludeAutoSubs(bool enabled) async {
    return _localDatasource.saveIncludeAutoSubs(enabled);
  }

  @override
  Future<bool> saveWriteThumbnail(bool enabled) async {
    return _localDatasource.saveWriteThumbnail(enabled);
  }

  @override
  Future<bool> saveEmbedThumbnail(bool enabled) async {
    return _localDatasource.saveEmbedThumbnail(enabled);
  }

  @override
  Future<bool> saveEmbedMetadata(bool enabled) async {
    return _localDatasource.saveEmbedMetadata(enabled);
  }

  @override
  Future<bool> saveEmbedChapters(bool enabled) async {
    return _localDatasource.saveEmbedChapters(enabled);
  }

  @override
  Future<bool> saveSponsorBlockEnabled(bool enabled) async {
    return _localDatasource.saveSponsorBlockEnabled(enabled);
  }

  @override
  Future<bool> saveSponsorBlockAction(String action) async {
    return _localDatasource.saveSponsorBlockAction(action);
  }

  @override
  Future<bool> saveSponsorBlockCategories(List<String> categories) async {
    return _localDatasource.saveSponsorBlockCategories(categories);
  }

  // ==================== P1 FEATURES ====================

  @override
  Future<bool> saveForceRemux(bool enabled) async {
    return _localDatasource.saveForceRemux(enabled);
  }

  // ==================== P2 FEATURES ====================

  @override
  Future<bool> saveTiktokRemoveWatermark(bool enabled) async {
    return _localDatasource.saveTiktokRemoveWatermark(enabled);
  }

  // ==================== P3 FEATURES ====================

  @override
  Future<bool> saveProxyUrl(String? url) async {
    return _localDatasource.saveProxyUrl(url);
  }

  @override
  Future<bool> saveProxyList(List<String> proxies) async {
    return _localDatasource.saveProxyList(proxies);
  }

  @override
  Future<bool> saveGeoBypass(bool enabled) async {
    return _localDatasource.saveGeoBypass(enabled);
  }

  @override
  Future<bool> saveGeoBypassCountry(String? country) async {
    return _localDatasource.saveGeoBypassCountry(country);
  }

  @override
  Future<bool> saveArchiveEnabled(bool enabled) async {
    return _localDatasource.saveArchiveEnabled(enabled);
  }

  @override
  Future<bool> saveAutoRetryEnabled(bool enabled) async {
    return _localDatasource.saveAutoRetryEnabled(enabled);
  }

  @override
  Future<bool> saveDateAfter(String? date) async {
    return _localDatasource.saveDateAfter(date);
  }

  @override
  Future<bool> saveDateBefore(String? date) async {
    return _localDatasource.saveDateBefore(date);
  }

  @override
  Future<bool> saveMinDuration(int? seconds) async {
    return _localDatasource.saveMinDuration(seconds);
  }

  @override
  Future<bool> saveMaxDuration(int? seconds) async {
    return _localDatasource.saveMaxDuration(seconds);
  }

  // ==================== NETWORK TUNING ====================

  @override
  Future<bool> saveSocketTimeout(int seconds) async {
    return _localDatasource.saveSocketTimeout(seconds);
  }

  @override
  Future<bool> saveMaxRetries(int retries) async {
    return _localDatasource.saveMaxRetries(retries);
  }

  @override
  Future<bool> saveHttpChunkSizeMb(int sizeMb) async {
    return _localDatasource.saveHttpChunkSizeMb(sizeMb);
  }

  @override
  Future<bool> saveMaxSegments(int segments) async {
    return _localDatasource.saveMaxSegments(segments);
  }

  // ==================== OUTPUT FILENAME TEMPLATE ====================

  @override
  Future<bool> saveFilenameTemplate(String template) async {
    return _localDatasource.saveFilenameTemplate(template);
  }

  // ==================== CUSTOM POSTPROCESSOR ARGS ====================

  @override
  Future<bool> saveCustomPostprocessorArgs(String args) async {
    return _localDatasource.saveCustomPostprocessorArgs(args);
  }

  @override
  Future<bool> saveDownloadsViewMode(String mode) async {
    return _localDatasource.saveDownloadsViewMode(mode);
  }

  // ==================== POST-DOWNLOAD ACTIONS ====================

  @override
  Future<bool> savePostDownloadAction(PostDownloadAction action) async {
    return _localDatasource.savePostDownloadAction(action);
  }

  @override
  Future<bool> savePostDownloadTargetFolder(String folder) async {
    return _localDatasource.savePostDownloadTargetFolder(folder);
  }

  // ==================== PLAYER SETTINGS ====================

  @override
  Future<bool> saveBackgroundAudioEnabled(bool enabled) async {
    return _localDatasource.saveBackgroundAudioEnabled(enabled);
  }

  @override
  Future<bool> saveSystemPipEnabled(bool enabled) async {
    return _localDatasource.saveSystemPipEnabled(enabled);
  }

  @override
  Future<bool> saveGlobalBandwidthLimit(int kbps) async {
    return _localDatasource.saveGlobalBandwidthLimit(kbps);
  }

  @override
  Future<bool> saveWifiOnlyMode(bool enabled) async {
    return _localDatasource.saveWifiOnlyMode(enabled);
  }

  @override
  Future<bool> saveAutoThrottle(bool enabled) async {
    return _localDatasource.saveAutoThrottle(enabled);
  }

  @override
  Future<bool> saveAdaptiveSegments(bool enabled) async {
    return _localDatasource.saveAdaptiveSegments(enabled);
  }

  @override
  Future<bool> saveNetworkAwareQueueReorder(bool enabled) async {
    return _localDatasource.saveNetworkAwareQueueReorder(enabled);
  }

  @override
  Future<bool> saveQuietHoursEnabled(bool enabled) async {
    return _localDatasource.saveQuietHoursEnabled(enabled);
  }

  @override
  Future<bool> saveQuietHoursStart(int hour) async {
    return _localDatasource.saveQuietHoursStart(hour);
  }

  @override
  Future<bool> saveQuietHoursEnd(int hour) async {
    return _localDatasource.saveQuietHoursEnd(hour);
  }

  @override
  Future<bool> saveQuietHoursBandwidthKbps(int kbps) async {
    return _localDatasource.saveQuietHoursBandwidthKbps(kbps);
  }

  @override
  Future<bool> clearSettings() async {
    return _localDatasource.clearAll();
  }

  DownloadFileType _legacyFileType(QualityPreference preferredQuality) {
    if (preferredQuality == QualityPreference.audioOnly) {
      return DownloadFileType.audio;
    }
    return DownloadFileType.video;
  }

  DownloadQualityIntent _legacyQualityIntent(
    QualityPreference preferredQuality,
  ) {
    switch (preferredQuality) {
      case QualityPreference.auto:
      case QualityPreference.audioOnly:
        return DownloadQualityIntent.recommended;
      case QualityPreference.best:
        return DownloadQualityIntent.bestAvailable;
      case QualityPreference.p1080:
      case QualityPreference.p720:
      case QualityPreference.p480:
        return DownloadQualityIntent.specific;
    }
  }

  PortableQualityTarget? _legacyQualityTarget(
    QualityPreference preferredQuality,
  ) {
    switch (preferredQuality) {
      case QualityPreference.p1080:
        return const PortableQualityTarget.video(targetHeight: 1080);
      case QualityPreference.p720:
        return const PortableQualityTarget.video(targetHeight: 720);
      case QualityPreference.p480:
        return const PortableQualityTarget.video(targetHeight: 480);
      case QualityPreference.auto:
      case QualityPreference.best:
      case QualityPreference.audioOnly:
        return null;
    }
  }
}
