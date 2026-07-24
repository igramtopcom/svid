import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../config/brand_config.dart';

/// Application localization helper
/// Provides easy access to translated strings throughout the app
class AppLocalizations {
  AppLocalizations._();

  /// Shared namedArgs for all translation keys that contain {appName}.
  /// Defined once — every .tr() call that embeds the brand name uses this.
  static Map<String, String> get _brandArgs => {
    'appName': BrandConfig.current.appName,
  };

  // ==================== APP ====================

  /// App name is a proper noun — resolved directly from BrandConfig, not localization.
  static String get appName => BrandConfig.current.appName;
  static String get appTitle => BrandConfig.current.appName;
  static String get appSubtitle => 'app.subtitle'.tr();

  // ==================== NAVIGATION ====================

  static String get navHome => 'navigation.home'.tr();
  static String get navAll => 'navigation.all'.tr();
  static String get navVideo => 'navigation.video'.tr();
  static String get navAudio => 'navigation.audio'.tr();
  static String get navImage => 'navigation.image'.tr();
  static String get navPlaylist => 'navigation.playlist'.tr();
  static String get navSettings => 'navigation.settings'.tr();
  static String get navSupport => 'navigation.support'.tr();
  static String get navAssistant => 'navigation.assistant'.tr();
  static String get navSubscriptions => 'navigation.subscriptions'.tr();
  static String get navSearch => 'navigation.search'.tr();
  static String get navNewDownload => 'navigation.newDownload'.tr();
  static String get navBrowser => 'navigation.browser'.tr();
  static String get navConverter => 'navigation.converter'.tr();

  // ==================== PLAYER ====================

  static String get playerExpand => 'player.expand'.tr();
  static String get playerClose => 'player.close'.tr();
  static String playerPreviewBannerLabel(int percent) =>
      'player.previewBannerLabel'.tr(namedArgs: {'percent': '$percent'});
  static String get playerPreviewBannerNoProgress =>
      'player.previewBannerNoProgress'.tr();
  static String get playerAudio => 'player.audio'.tr();
  static String get playerVideo => 'player.video'.tr();
  static String get playerAudioTrack => 'player.audioTrack'.tr();
  static String get playerAudioTrackNone => 'player.audioTrackNone'.tr();
  static String get playerSubtitleDelay => 'player.subtitleDelay'.tr();
  static String get playerSubtitleDelayReset =>
      'player.subtitleDelayReset'.tr();
  static String get playerDone => 'player.done'.tr();
  static String get playerPrefsCleared => 'player.prefsCleared'.tr();
  static String get playerPrefsSaved => 'player.prefsSaved'.tr();
  static String get playerBackgroundAudio => 'player.backgroundAudio'.tr();
  static String get playerBackgroundAudioDesc =>
      'player.backgroundAudioDesc'.tr();
  static String get playerSystemPip => 'player.systemPip'.tr();
  static String get playerSystemPipDesc => 'player.systemPipDesc'.tr();
  static String get playerAudioPlayerTitle => 'player.audioPlayerTitle'.tr();
  static String get playerOpenMiniPlayer => 'player.openMiniPlayer'.tr();
  static String get playerPlaybackSpeed => 'player.playbackSpeed'.tr();
  static String get playerKeyboardShortcutsHint =>
      'player.keyboardShortcutsHint'.tr();
  static String get playerRewind10s => 'player.rewind10s'.tr();
  static String get playerForward10s => 'player.forward10s'.tr();
  static String get playerPause => 'player.pause'.tr();
  static String get playerPlay => 'player.play'.tr();
  static String get playerToggleMute => 'player.toggleMute'.tr();
  static String get playerPreviewNotAvailable =>
      'player.previewNotAvailable'.tr();
  static String get playerSubtitle => 'player.subtitle'.tr();
  static String get playerSubtitles => 'player.subtitles'.tr();
  static String get playerSubtitlesAndAudio => 'player.subtitlesAndAudio'.tr();
  static String get playerSubtitleOff => 'player.subtitleOff'.tr();
  static String get playerSubtitleEmbedded => 'player.subtitleEmbedded'.tr();
  static String get playerSubtitleExternalFiles =>
      'player.subtitleExternalFiles'.tr();
  static String get playerVolume => 'player.volume'.tr();
  static String get playerResetZoom => 'player.resetZoom'.tr();
  static String get playerZoomIn => 'player.zoomIn'.tr();
  static String get playerZoomOut => 'player.zoomOut'.tr();
  static String get playerFitToScreen => 'player.fitToScreen'.tr();
  static String get playerImageInfo => 'player.imageInfo'.tr();
  static String get playerImageLoadFailed => 'player.imageLoadFailed'.tr();
  static String get playerImageInformation => 'player.imageInformation'.tr();
  static String get playerInfoFilename => 'player.infoFilename'.tr();
  static String get playerInfoSize => 'player.infoSize'.tr();
  static String get playerInfoLocation => 'player.infoLocation'.tr();
  static String get playerInfoFormat => 'player.infoFormat'.tr();
  static String get playerInfoDownloaded => 'player.infoDownloaded'.tr();
  static String get playerChapters => 'player.chapters'.tr();
  static String get playerExitTrimMode => 'player.exitTrimMode'.tr();
  static String get playerTrimVideo => 'player.trimVideo'.tr();
  static String get playerPictureInPicture => 'player.pictureInPicture'.tr();
  static String get playerSettings => 'player.settings'.tr();
  static String get playerSpeedNormal => 'player.speedNormal'.tr();
  static String get playerAspectRatio => 'player.aspectRatio'.tr();
  static String get playerAspectFit => 'player.aspectFit'.tr();
  static String get playerAspectFill => 'player.aspectFill'.tr();
  static String get playerAspectStretch => 'player.aspectStretch'.tr();
  static String get playerAspectOriginal => 'player.aspectOriginal'.tr();
  static String get playerFullscreen => 'player.fullscreen'.tr();
  static String get playerExitFullscreen => 'player.exitFullscreen'.tr();
  static String get playerTrimPreview => 'player.trimPreview'.tr();
  static String get playerTrimReset => 'player.trimReset'.tr();
  static String get playerTrimExport => 'player.trimExport'.tr();
  static String get playerTrimFastTitle => 'player.trim.fastTitle'.tr();
  static String get playerTrimFastSubtitle => 'player.trim.fastSubtitle'.tr();
  static String get playerTrimPreciseTitle => 'player.trim.preciseTitle'.tr();
  static String get playerTrimPreciseSubtitle =>
      'player.trim.preciseSubtitle'.tr();
  static String get playerTrimShowInFinder => 'player.trim.showInFinder'.tr();
  static String get playerControlsScreenshotSaved =>
      'player.controls.screenshotSaved'.tr();
  static String get playerControlsScreenshotFailed =>
      'player.controls.screenshotFailed'.tr();
  static String get playerControlsScreenshotTooltip =>
      'player.controls.screenshotTooltip'.tr();
  static String get playerControlsEditTooltip =>
      'player.controls.editTooltip'.tr();
  static String get playerControlsCinemaModeTooltip =>
      'player.controls.cinemaModeTooltip'.tr();
  static String get playerSubtitlesChange => 'player.subtitlesChange'.tr();
  static String get browserBookmarksExportHtml =>
      'browser.bookmarksExportHtml'.tr();
  static String get browserBookmarksExportJson =>
      'browser.bookmarksExportJson'.tr();
  static String get browserBookmarksSearchHint =>
      'browser.bookmarksSearchHint'.tr();
  static String get browserMediaSniffOpenSpecificVideo =>
      'browser.mediaSniffOpenSpecificVideo'.tr();
  static String floatingCaptureErrorDuplicateDownload(String filename) =>
      'floatingCapture.errorDuplicateDownload'.tr(
        namedArgs: {'filename': filename},
      );
  static String get floatingCaptureErrorInsufficientDiskSpace =>
      'floatingCapture.errorInsufficientDiskSpace'.tr();
  static String get settingsNetworkAdaptiveSegments =>
      'settingsNetwork.adaptiveSegments'.tr();
  static String get settingsNetworkQuietHours =>
      'settingsNetwork.quietHours'.tr();
  static String get settingsNetworkStartTime =>
      'settingsNetwork.startTime'.tr();
  static String get settingsNetworkEndTime => 'settingsNetwork.endTime'.tr();
  static String get settingsNetworkBandwidthLimit =>
      'settingsNetwork.bandwidthLimit'.tr();
  static String get settingsNetworkProxyRotation =>
      'settingsNetwork.proxyRotation'.tr();
  static String get settingsNetworkQuietHoursBandwidth =>
      'settingsNetwork.quietHoursBandwidth'.tr();
  static String get settingsNetworkLimitLabel =>
      'settingsNetwork.limitLabel'.tr();
  static String get settingsNetworkLimitHelper =>
      'settingsNetwork.limitHelper'.tr();
  static String get settingsNetworkProxyUrl => 'settingsNetwork.proxyUrl'.tr();
  static String get settingsNetworkAddProxy => 'settingsNetwork.addProxy'.tr();
  static String get settingsPlatformsTitle => 'settingsPlatforms.title'.tr();
  static String get settingsQualityUnlimited =>
      'settingsQuality.unlimited'.tr();
  static String get converterOverlayPositionTop =>
      'converter.overlayPositionTop'.tr();
  static String get converterOverlayPositionCenter =>
      'converter.overlayPositionCenter'.tr();
  static String get converterOverlayPositionBottom =>
      'converter.overlayPositionBottom'.tr();
  static String converterSubsCount(int count) =>
      'converter.subsCount'.tr(namedArgs: {'count': '$count'});
  static String get playlistFallbackTitle => 'playlist.fallbackTitle'.tr();

  // ==================== BUILT-IN PRESETS (settings → quality presets) ====================
  // Resolves preset displayName via stable preset ID. The seeded `name`
  // field in DB is treated as a fallback only — UI must call
  // [builtinPresetName] when `preset.isBuiltIn` so locale switch is live.
  static String builtinPresetName(String presetId) =>
      'builtinPreset.$presetId'.tr();

  // ==================== SMART CTA BUTTON (home command bar) ====================
  // Primary action label rendered by `SmartCtaButton._labelFor()`. Each
  // smart-intent state holds one key — em hold one key per state, KHÔNG
  // concat literals in widget code.
  static String get smartCtaAnalyzing => 'smartCta.analyzing'.tr();
  static String get smartCtaDownload => 'smartCta.download'.tr();
  static String get smartCtaBatchDownload => 'smartCta.batchDownload'.tr();
  static String get smartCtaViewPlaylist => 'smartCta.viewPlaylist'.tr();
  static String get smartCtaViewChannel => 'smartCta.viewChannel'.tr();
  static String get smartCtaSearch => 'smartCta.search'.tr();
  static String get smartCtaOpenBrowser => 'smartCta.openBrowser'.tr();

  // ==================== FLOATING CAPTURE (system notification toasts) ====================
  // Notification body strings rendered by `local_notifier` from main.dart's
  // capture lifecycle hooks. Title is composed as "{appName} — {section}".
  static String get captureNotifySnoozedTitle =>
      'capture.notifySnoozedTitle'.tr();
  static String get captureNotifySnoozedBody =>
      'capture.notifySnoozedBody'.tr();
  static String get captureNotifyDeduplicatedBody =>
      'capture.notifyDeduplicatedBody'.tr();

  // ==================== HOME — platform shortcuts + imported preset + tooltip ====================
  static String get homePlatformShortcutOther =>
      'home.platformShortcutOther'.tr();
  static String homeImportedPresetName(String platform) =>
      'home.importedPresetName'.tr(namedArgs: {'platform': platform});
  static String get homeCarouselClickHint => 'home.carouselClickHint'.tr();
  static String get homeMuteToggleTooltip => 'home.muteToggleTooltip'.tr();

  // ==================== ENUM displayName helpers (Tier 3) ====================
  // Pattern: enum value name → i18n key under the enum's namespace. Each
  // enum exposes a `localizedLabel` getter that calls into here so the
  // const-enum constraint (can't call .tr() at declaration) is bypassed
  // without changing the enum surface. Mirrors `download_error_code.dart`.
  static String conversionStatusLabel(String name) =>
      'conversionStatus.$name'.tr();
  static String outputFormatCategoryLabel(String name) =>
      'outputFormatCategory.$name'.tr();
  static String watermarkPositionLabel(String name) =>
      'watermarkPosition.$name'.tr();
  static String mediaTypeLabel(String name) => 'mediaType.$name'.tr();
  static String get resolutionOriginal => 'resolution.original'.tr();
  static String get resolutionCustom => 'resolution.custom'.tr();

  // ==================== KEYBOARD SHORTCUTS DIALOG (Tier 5) ====================
  // Whole `KeyboardShortcutsDialog` is built from this namespace. Keys
  // ('Space', 'K', 'Cmd+T') stay as code-literal because they're universal
  // tech tokens; only section titles + descriptions translate.
  static String get keyboardShortcutsDialogTitle =>
      'keyboardShortcuts.dialogTitle'.tr();
  static String keyboardShortcutsSection(String name) =>
      'keyboardShortcuts.section.$name'.tr();
  static String keyboardShortcutsItem(String name) =>
      'keyboardShortcuts.item.$name'.tr();

  // ==================== SYSTEM NOTIFICATIONS (Tier 4) ====================
  // Titles + action labels rendered into OS-level LocalNotification popups
  // by `lib/core/services/notification_service.dart`. Emoji prefix is part
  // of the source token (cross-locale consistent badge), translation only
  // covers the descriptive text after.
  static String get notificationDownloadCompleted =>
      'notification.downloadCompleted'.tr();
  static String get notificationDownloadFailed =>
      'notification.downloadFailed'.tr();
  static String get notificationDownloadStarted =>
      'notification.downloadStarted'.tr();
  static String get notificationOpenFolder => 'notification.openFolder'.tr();

  // ==================== ERROR DIAGNOSTICS (assistant) ====================
  // Per-error-code labels/descriptions resolved at runtime. The underlying
  // DownloadErrorCode enum IDs are stable logic keys — only the rendered
  // labels and descriptions localize. Action label/description IDs are
  // unique per (errorCode, position) so each diagnostic message stays
  // contextually accurate (e.g. autoRetryNetwork vs autoRetryRate share
  // type but render different copy).
  static String get diagnosticsTitlePatternPrefix =>
      'diagnostics.titlePatternPrefix'.tr();
  static String diagnosticsPatternSummary({
    required String base,
    required int count,
    required String span,
    required String platform,
    required String healedNote,
  }) => 'diagnostics.patternSummary'.tr(
    namedArgs: {
      'base': base,
      'count': '$count',
      'span': span,
      'platform': platform,
      'healedNote': healedNote,
    },
  );
  static String diagnosticsPatternHealedSome(int count) =>
      'diagnostics.patternHealedSome'.tr(namedArgs: {'count': '$count'});
  static String get diagnosticsPatternHealedNone =>
      'diagnostics.patternHealedNone'.tr();
  static String get diagnosticsPlatformFallback =>
      'diagnostics.platformFallback'.tr();

  /// Locale-aware unit suffix for an `ErrorPattern.timeSpan` value.
  /// Picks minutes / hours / days based on which bucket the duration falls in
  /// (matches the original Dart logic in `ErrorPattern.timeSpan`). Each
  /// translation owns the unit *and* spacing convention (no space in
  /// CJK locales, narrow space in fr/ru, etc.).
  static String diagnosticsTimeSpan({
    required int minutes,
    required int hours,
    required int days,
  }) {
    if (minutes < 60) {
      return 'diagnostics.timeSpanMinutes'.tr(namedArgs: {'count': '$minutes'});
    }
    if (hours < 24) {
      return 'diagnostics.timeSpanHours'.tr(namedArgs: {'count': '$hours'});
    }
    return 'diagnostics.timeSpanDays'.tr(namedArgs: {'count': '$days'});
  }

  static String diagnosticsExplanation(String codeName) =>
      'diagnostics.explanation.$codeName'.tr();
  static String diagnosticsActionLabel(String actionId) =>
      'diagnostics.action.${actionId}Label'.tr();
  static String diagnosticsActionDesc(String actionId) =>
      'diagnostics.action.${actionId}Desc'.tr();

  static String get playerAbClear => 'player.abClear'.tr();
  static String get playerAbSetPointA => 'player.abSetPointA'.tr();
  static String get playerAbSetPointB => 'player.abSetPointB'.tr();
  static String get playerBack => 'player.back'.tr();
  static String get playerNext => 'player.next'.tr();
  static String get playerPrevious => 'player.previous'.tr();

  // ==================== YOUTUBE TAB ====================

  static String get youtubeTabTitle => 'youtube.tabTitle'.tr();
  static String get youtubeTabDescription => 'youtube.tabDescription'.tr();
  static String get youtubeSearchAction => 'youtube.searchAction'.tr();

  // ==================== HOME ====================

  static String get homeTitle => 'home.title'.tr(namedArgs: _brandArgs);
  static String get homeSubtitle => 'home.subtitle'.tr();
  static String get homeUrlLabel => 'home.urlLabel'.tr();
  static String get homeUrlHint => 'home.urlHint'.tr();
  static String get homeDropUrlHint => 'home.dropUrlHint'.tr();
  static String get homeUrlRequired => 'home.urlRequired'.tr();
  static String get homeUrlInvalid => 'home.urlInvalid'.tr();
  static String get homeStartDownload => 'home.startDownload'.tr();

  // Adaptive CTA labels — see [GlassmorphismHeader._adaptiveCtaLabel].
  // The home command bar swaps its primary button label to follow the
  // smart-input classification: keyword text → search, channel /
  // playlist URL → view-channel / view-playlist, multi-URL paste →
  // batch, unsupported HTTP URL → open-in-browser.
  static String get homeCtaSearch => 'home.cta.search'.tr();
  static String get homeCtaViewChannel => 'home.cta.viewChannel'.tr();
  static String get homeCtaViewPlaylist => 'home.cta.viewPlaylist'.tr();
  static String get homeCtaBatchDownload => 'home.cta.batchDownload'.tr();
  static String get homeCtaOpenBrowser => 'home.cta.openBrowser'.tr();

  // Free-tier quota strip — V2 mockup-aligned inline banner showing
  // remaining daily downloads + upgrade CTA. Visible only when the
  // current user is on the free plan; premium hides the strip.
  static String get homeQuotaFreePlan => 'home.quota.freePlan'.tr();
  static String homeQuotaRemaining(int count) =>
      'home.quota.remaining'.tr(namedArgs: {'count': '$count'});
  static String get homeQuotaExhausted => 'home.quota.exhausted'.tr();
  static String get homeQuotaUpgradeCta => 'home.quota.upgradeCta'.tr();

  // V2 command-bar section labels — "Link hoặc từ khóa" caption above
  // the input card; vertical stack labels under the History + Batch
  // icon buttons (mockup pattern).
  static String get homeSectionLinkOrKeyword =>
      'home.sectionLinkOrKeyword'.tr();
  static String get homeHistoryButton => 'home.historyButton'.tr();
  static String get homeBatchButton => 'home.batchButton'.tr();
  static String get homeDownloadsHistoryTab => 'home.downloads.historyTab'.tr();
  static String get homeDownloadsAllTab => 'home.downloads.allTab'.tr();
  static String get homeDownloadsQueueTab => 'home.downloads.queueTab'.tr();
  static String get homeDownloadsQueueEmpty => 'home.downloads.queueEmpty'.tr();
  static String get homeDownloadsQueueEmptySubtitle =>
      'home.downloads.queueEmptySubtitle'.tr();
  static String homeDownloadsQueueCount(int count) =>
      'home.downloads.queueCount'.tr(namedArgs: {'count': '$count'});

  // V2 preset chip + popover (Box 1) — labels for the command bar's
  // "MP4 · 1080p ▾" trigger and its dropdown rows. Phase A renders
  // static layout; Phase B wires live values from
  // [ActivePresetController].
  static String get homePresetPopoverTitle => 'home.preset.popoverTitle'.tr();
  static String get homePresetProfile => 'home.preset.profile'.tr();
  static String get homePresetProfilePickerTitle =>
      'home.preset.profilePickerTitle'.tr();
  static String get homePresetBuiltIn => 'home.preset.builtIn'.tr();
  static String get homePresetModifiedShort => 'home.preset.modifiedShort'.tr();
  static String get homePresetFormat => 'home.preset.format'.tr();
  static String get homePresetFormatAuto => 'home.preset.formatAuto'.tr();
  static String get homePresetFormatMp4Desc => 'home.preset.formatMp4Desc'.tr();
  static String get homePresetFormatWebmDesc =>
      'home.preset.formatWebmDesc'.tr();
  static String get homePresetFormatMkvDesc => 'home.preset.formatMkvDesc'.tr();
  static String get homePresetFormatMp3Desc => 'home.preset.formatMp3Desc'.tr();
  static String get homePresetFormatM4aDesc => 'home.preset.formatM4aDesc'.tr();
  static String get homePresetFormatFlacDesc =>
      'home.preset.formatFlacDesc'.tr();
  static String get homePresetFormatOpusDesc =>
      'home.preset.formatOpusDesc'.tr();
  static String get homePresetFormatWavDesc => 'home.preset.formatWavDesc'.tr();
  static String get homePresetQuality => 'home.preset.quality'.tr();
  static String get homePresetQualityDefault =>
      'home.preset.qualityDefault'.tr();
  static String get homePresetQualityBestAvailable =>
      'home.preset.qualityBestAvailable'.tr();
  static String get homePresetFallback => 'home.preset.fallback'.tr();
  static String get homePresetFallbackNearest =>
      'home.preset.fallbackNearest'.tr();
  static String get homePresetFallbackHigher =>
      'home.preset.fallbackHigher'.tr();
  static String get homePresetFallbackBlock => 'home.preset.fallbackBlock'.tr();
  static String get homePresetFallbackNearestDesc =>
      'home.preset.fallbackNearestDesc'.tr();
  static String get homePresetFallbackHigherDesc =>
      'home.preset.fallbackHigherDesc'.tr();
  static String get homePresetFallbackBlockDesc =>
      'home.preset.fallbackBlockDesc'.tr();
  static String get homePresetBestQualityShort =>
      'home.preset.bestQualityShort'.tr();
  static String get homePresetSaveLocation => 'home.preset.saveLocation'.tr();
  static String get homePresetSaveLocationPickerTitle =>
      'home.preset.saveLocationPickerTitle'.tr();
  static String get homePresetAdvancedSettings =>
      'home.preset.advancedSettings'.tr();
  static String get homePresetManualMode => 'home.preset.manualMode'.tr();
  static String get homePresetManualModeShort =>
      'home.preset.manualModeShort'.tr();
  static String get homePresetManualModeOnDescription =>
      'home.preset.manualModeOnDescription'.tr();
  static String get homePresetManualModeOffDescription =>
      'home.preset.manualModeOffDescription'.tr();
  static String get homeProcessing => 'home.processing'.tr();
  static String get homeExtractionAnalyzing => 'home.extractionAnalyzing'.tr();
  static String get homeExtractionExtracting =>
      'home.extractionExtracting'.tr();
  static String get homeExtractionFetching => 'home.extractionFetching'.tr();
  static String get homeExtractionAlmostReady =>
      'home.extractionAlmostReady'.tr();
  static String get homePopularSites => 'home.popularSites'.tr();
  static String get homeOpenBrowser => 'home.openBrowser'.tr();
  static String get homeBrowser => 'home.browser'.tr();
  static String get homeRecentDownloads => 'home.recentDownloads'.tr();
  static String get homeClearCompleted => 'home.clearCompleted'.tr();
  static String get homeSearchPlaceholder => 'home.searchPlaceholder'.tr();
  static String get homeClearSearch => 'home.clearSearch'.tr();
  static String get homeNoResultsTitle => 'home.noResultsTitle'.tr();
  static String get homeNoResultsSubtitle => 'home.noResultsSubtitle'.tr();
  static String get homeUrlAutoPasted => 'home.urlAutoPasted'.tr();
  static String homeDownloadStarted(String title) =>
      'home.downloadStarted'.tr(namedArgs: {'title': title});
  static String homeDownloadFailed(String error) =>
      'home.downloadFailed'.tr(namedArgs: {'error': error});
  static String homePreferenceSaved(String platform, String quality) =>
      'home.preferenceSaved'.tr(
        namedArgs: {'platform': platform, 'quality': quality},
      );
  static String get homePreferenceSaveFailed =>
      'home.preferenceSaveFailed'.tr();
  static String homeAutoDownloading(String title, String platform) =>
      'home.autoDownloading'.tr(
        namedArgs: {'title': title, 'platform': platform},
      );
  static String homeAutoDownloadingByPreset(String preset, String quality) =>
      'home.autoDownloadingByPreset'.tr(
        namedArgs: {'preset': preset, 'quality': quality},
      );
  static String get homePasteTooltip => 'home.pasteTooltip'.tr();
  static String get homeMoreSettings => 'home.moreSettings'.tr();
  static String get homeBestQuality => 'home.bestQuality'.tr();
  static String get homeQuality1080p => 'home.quality1080p'.tr();
  static String get homeQuality720p => 'home.quality720p'.tr();
  static String get homeQuality480p => 'home.quality480p'.tr();
  static String get homeAudioOnly => 'home.audioOnly'.tr();
  static String get homeClear => 'home.clear'.tr();
  static String get homeFile => 'home.file'.tr();
  static String get homeFiles => 'home.files'.tr();
  static String homeStartedDownloading(int count, String unit) =>
      'home.startedDownloading'.tr(
        namedArgs: {'count': count.toString(), 'unit': unit},
      );
  static String get homeNoCompletedDownloads =>
      'home.noCompletedDownloads'.tr();
  static String get homeClearCompletedTitle => 'home.clearCompletedTitle'.tr();
  static String homeClearCompletedMessage(int count) =>
      'home.clearCompletedMessage'.plural(
        count,
        namedArgs: {'count': count.toString()},
      );
  static String homeCleared(int count) =>
      'home.cleared'.plural(count, namedArgs: {'count': count.toString()});
  static String homeDeleted(int count) =>
      'home.deleted'.plural(count, namedArgs: {'count': count.toString()});
  static String get homeBatchActions => 'home.batchActions'.tr();
  static String get homeClearFailed => 'home.clearFailed'.tr();
  static String get homePauseAll => 'home.pauseAll'.tr();
  static String get homeResumeAll => 'home.resumeAll'.tr();
  static String get homeNoFailedDownloads => 'home.noFailedDownloads'.tr();
  static String get homeClearFailedTitle => 'home.clearFailedTitle'.tr();
  static String homeClearFailedMessage(int count) => 'home.clearFailedMessage'
      .plural(count, namedArgs: {'count': count.toString()});
  static String get homePausedAll => 'home.pausedAll'.tr();
  static String get homeResumedAll => 'home.resumedAll'.tr();
  static String homeLoginTo(String platform) =>
      'home.loginTo'.tr(namedArgs: {'platform': platform});
  static String homeLoggedIn(String platform) =>
      'home.loggedIn'.tr(namedArgs: {'platform': platform});
  static String get homeLogout => 'home.logout'.tr();
  static String get homeLoginRequired => 'home.loginRequired'.tr();
  static String get homeLoginRequiredMessage =>
      'home.loginRequiredMessage'.tr();
  static String get homeExtractionInProgress =>
      'home.extractionInProgress'.tr();
  static String get homeExtractionHistoryTooltip =>
      'home.extractionHistoryTooltip'.tr();
  static String get homeQuickStart => 'home.quickStart'.tr();
  static String get homeKeyboardShortcuts => 'home.keyboardShortcuts'.tr();
  static String get homeRecentActivity => 'home.recentActivity'.tr();
  static String get homeSelectDownload => 'home.selectDownload'.tr();
  static String get homeDownloadDetails => 'home.downloadDetails'.tr();
  static String get homeStatus => 'home.statusLabel'.tr();
  static String get homeQuality => 'home.qualityLabel'.tr();
  static String get homeFormat => 'home.formatLabel'.tr();
  static String get homeDuration => 'home.durationLabel'.tr();
  static String get homeFileSize => 'home.fileSizeLabel'.tr();
  static String get homeDate => 'home.dateLabel'.tr();
  static String get homePlatform => 'home.platformLabel'.tr();
  static String get homeOpen => 'home.openFile'.tr();
  static String get homeEtaRemaining => 'home.etaRemaining'.tr();
  static String get homeInsufficientSpace => 'home.insufficientSpace'.tr();
  static String homeExtractionElapsed(int seconds) =>
      'home.extractionElapsed'.tr(namedArgs: {'seconds': seconds.toString()});
  static String homeRequiredUpdate(String version) =>
      'home.requiredUpdate'.tr(namedArgs: {'version': version});
  static String homeUpdateAvailable(String version) =>
      'home.updateAvailable'.tr(namedArgs: {'version': version});
  static String get homeDownload => 'home.download'.tr();

  // ==================== DOWNLOADS ====================

  static String get downloadsTitle => 'downloads.title'.tr();
  static String get downloadsAllDownloads => 'downloads.allDownloads'.tr();
  static String get downloadsVideoDownloads => 'downloads.videoDownloads'.tr();
  static String get downloadsAudioDownloads => 'downloads.audioDownloads'.tr();
  static String get downloadsImageDownloads => 'downloads.imageDownloads'.tr();
  static String get downloadsRefresh => 'downloads.refresh'.tr();
  static String get downloadsEmptyTitle => 'downloads.emptyTitle'.tr();
  static String get downloadsEmptySubtitle => 'downloads.emptySubtitle'.tr();
  static String get downloadsEmptyPasteAction =>
      'downloads.emptyPasteAction'.tr();
  static String get downloadsEmptyOpenBrowserAction =>
      'downloads.emptyOpenBrowserAction'.tr();
  static String get downloadsEmptyPlatformHint =>
      'downloads.emptyPlatformHint'.tr();
  static String get downloadsPause => 'downloads.pause'.tr();
  static String get downloadsResume => 'downloads.resume'.tr();
  static String get downloadsCancel => 'downloads.cancel'.tr();
  static String get downloadsRetry => 'downloads.retry'.tr();
  static String downloadsCircuitBreakerOpen(String platform, int seconds) =>
      'downloads.circuitBreakerOpen'.tr(
        namedArgs: {'platform': platform, 'seconds': '$seconds'},
      );
  static String downloadsCircuitBreakerHalfOpen(String platform) =>
      'downloads.circuitBreakerHalfOpen'.tr(namedArgs: {'platform': platform});
  static String get downloadsDelete => 'downloads.delete'.tr();
  static String get downloadsDeleteDialogTitle =>
      'downloads.deleteDialogTitle'.tr();
  static String downloadsDeleteDialogMessage(String filename) =>
      'downloads.deleteDialogMessage'.tr(namedArgs: {'filename': filename});
  static String get downloadsDeleteRecordOnly =>
      'downloads.deleteRecordOnly'.tr();
  static String get downloadsDeleteFileAndRecord =>
      'downloads.deleteFileAndRecord'.tr();
  static String get downloadsOpenLocation => 'downloads.openLocation'.tr();
  static String get downloadsCopyUrl => 'downloads.copyUrl'.tr();
  static String get downloadsShareLink => 'downloads.shareLink'.tr();
  static String get downloadsFileInfo => 'downloads.fileInfo'.tr();
  static String get downloadsUrlCopied => 'downloads.urlCopied'.tr();
  static String get downloadsLocationOpened => 'downloads.locationOpened'.tr();
  static String get downloadsAllPlatforms => 'downloads.allPlatforms'.tr();
  static String get downloadsAllFormats => 'downloads.allFormats'.tr();
  static String get downloadsSortBy => 'downloads.sortBy'.tr();
  static String get downloadsFileMissing => 'downloads.fileMissing'.tr();
  static String get downloadsFileMissingError =>
      'downloads.fileMissingError'.tr();
  static String get downloadsRedownload => 'downloads.redownload'.tr();
  static String get downloadsCleanMissing => 'downloads.cleanMissing'.tr();
  static String downloadsCleanMissingDone(int count) =>
      'downloads.cleanMissingDone'.tr(namedArgs: {'count': '$count'});
  static String get downloadsViewAll => 'downloads.viewAll'.tr();

  // ==================== SORT OPTIONS ====================

  static String get sortDateNewest => 'sort.dateNewest'.tr();
  static String get sortDateOldest => 'sort.dateOldest'.tr();
  static String get sortNameAZ => 'sort.nameAZ'.tr();
  static String get sortNameZA => 'sort.nameZA'.tr();
  static String get sortSizeLargest => 'sort.sizeLargest'.tr();
  static String get sortSizeSmallest => 'sort.sizeSmallest'.tr();
  static String get sortStatus => 'sort.status'.tr();
  static String get sortDurationLongest => 'sort.durationLongest'.tr();
  static String get sortDurationShortest => 'sort.durationShortest'.tr();
  static String get sortViewsHighest => 'sort.viewsHighest'.tr();
  static String get sortUploaderAZ => 'sort.uploaderAZ'.tr();

  // ==================== DOWNLOAD FILTERS ====================

  static String get downloadFilterClearAll => 'downloadFilter.clearAll'.tr();
  static String get downloadFilterStatusFilter =>
      'downloadFilter.statusFilter'.tr();
  static String downloadFilterActiveFilters(int count) =>
      'downloadFilter.activeFilters'.tr(namedArgs: {'count': count.toString()});

  // ==================== A-B REPEAT ====================

  static String get abRepeatSetPointA => 'abRepeat.setPointA'.tr();
  static String get abRepeatSetPointB => 'abRepeat.setPointB'.tr();
  static String get abRepeatClearLoop => 'abRepeat.clearLoop'.tr();
  static String abRepeatPointASet(String time) =>
      'abRepeat.pointASet'.tr(namedArgs: {'time': time});
  static String abRepeatPointBSet(String time) =>
      'abRepeat.pointBSet'.tr(namedArgs: {'time': time});
  static String get abRepeatCleared => 'abRepeat.cleared'.tr();
  static String get abRepeatInvalidB => 'abRepeat.invalidB'.tr();

  // ==================== SUBTITLE APPEARANCE ====================
  static String get subtitleAppearanceTitle => 'subtitleAppearance.title'.tr();
  static String get subtitleAppearanceFontSize =>
      'subtitleAppearance.fontSize'.tr();
  static String get subtitleAppearanceTextColor =>
      'subtitleAppearance.textColor'.tr();
  static String get subtitleAppearanceBackground =>
      'subtitleAppearance.background'.tr();
  static String get subtitleAppearanceBackgroundOpacity =>
      'subtitleAppearance.backgroundOpacity'.tr();
  static String get subtitleAppearancePosition =>
      'subtitleAppearance.position'.tr();
  static String get subtitleAppearancePreview =>
      'subtitleAppearance.preview'.tr();
  static String get subtitleAppearanceResetDefault =>
      'subtitleAppearance.resetDefault'.tr();
  static String get subtitleAppearanceLoadFile =>
      'subtitleAppearance.loadFile'.tr();
  static String get subtitleAppearanceAppearance =>
      'subtitleAppearance.appearance'.tr();

  // ==================== SUBTITLE SEARCH (OpenSubtitles) ====================
  static String get subtitleSearchTitle => 'subtitleSearch.title'.tr();
  static String get subtitleSearchHint => 'subtitleSearch.hint'.tr();
  static String get subtitleSearchButton => 'subtitleSearch.button'.tr();
  static String get subtitleSearchApiKeyLabel =>
      'subtitleSearch.apiKeyLabel'.tr();
  static String get subtitleSearchApiKeyHint =>
      'subtitleSearch.apiKeyHint'.tr();
  static String get subtitleSearchApiKeySave =>
      'subtitleSearch.apiKeySave'.tr();
  static String get subtitleSearchApiKeyRequired =>
      'subtitleSearch.apiKeyRequired'.tr();
  static String get subtitleSearchNoResults => 'subtitleSearch.noResults'.tr();
  static String get subtitleSearchDownloading =>
      'subtitleSearch.downloading'.tr();
  static String get subtitleSearchSaved => 'subtitleSearch.saved'.tr();
  static String get subtitleSearchError => 'subtitleSearch.error'.tr();
  static String get subtitleSearchOnline => 'subtitleSearch.online'.tr();

  // ==================== MEDIA INFO ====================

  static String get mediaInfoTitle => 'mediaInfo.title'.tr();
  static String get mediaInfoVideo => 'mediaInfo.video'.tr();
  static String get mediaInfoAudio => 'mediaInfo.audio'.tr();
  static String get mediaInfoFile => 'mediaInfo.file'.tr();
  static String get mediaInfoCodec => 'mediaInfo.codec'.tr();
  static String get mediaInfoResolution => 'mediaInfo.resolution'.tr();
  static String get mediaInfoFrameRate => 'mediaInfo.frameRate'.tr();
  static String get mediaInfoBitrate => 'mediaInfo.bitrate'.tr();
  static String get mediaInfoPixelFormat => 'mediaInfo.pixelFormat'.tr();
  static String get mediaInfoChannels => 'mediaInfo.channels'.tr();
  static String get mediaInfoSampleRate => 'mediaInfo.sampleRate'.tr();
  static String get mediaInfoFileName => 'mediaInfo.fileName'.tr();
  static String get mediaInfoFileSize => 'mediaInfo.fileSize'.tr();

  // ==================== DOWNLOAD STATUS ====================

  static String get statusPending => 'downloadStatus.pending'.tr();
  static String get statusExtracting => 'downloadStatus.extracting'.tr();
  static String get statusQueued => 'downloadStatus.queued'.tr();
  static String get statusActive => 'downloadStatus.active'.tr();
  static String get statusPaused => 'downloadStatus.paused'.tr();
  static String get statusCompleted => 'downloadStatus.completed'.tr();
  static String get statusFailed => 'downloadStatus.failed'.tr();
  static String get statusCancelled => 'downloadStatus.cancelled'.tr();
  static String get statusPostProcessing =>
      'downloadStatus.postProcessing'.tr();
  static String get statusMerging => 'downloadStatus.merging'.tr();
  static String get statusRemuxing => 'downloadStatus.remuxing'.tr();
  static String get statusConverting => 'downloadStatus.converting'.tr();
  static String get statusWaitingForNetwork =>
      'downloadStatus.waitingForNetwork'.tr();

  // Priority labels (used by DownloadPriority.displayLabel)
  static String get priorityHigh => 'downloadPriority.high'.tr();
  static String get priorityNormal => 'downloadPriority.normal'.tr();
  static String get priorityLow => 'downloadPriority.low'.tr();

  // ==================== PLATFORMS ====================

  static String get platformYoutube => 'platforms.youtube'.tr();
  static String get platformTiktok => 'platforms.tiktok'.tr();
  static String get platformInstagram => 'platforms.instagram'.tr();
  static String get platformTwitter => 'platforms.twitter'.tr();
  static String get platformFacebook => 'platforms.facebook'.tr();
  static String get platformVimeo => 'platforms.vimeo'.tr();
  static String get platformDailymotion => 'platforms.dailymotion'.tr();
  static String get platformSoundcloud => 'platforms.soundcloud'.tr();
  static String get platformBilibili => 'platforms.bilibili'.tr();
  static String get platformReddit => 'platforms.reddit'.tr();
  static String get platformPinterest => 'platforms.pinterest'.tr();
  static String get platformLinkedin => 'platforms.linkedin'.tr();
  static String get platformDouyin => 'platforms.douyin'.tr();
  static String get platformThreads => 'platforms.threads'.tr();
  static String get platformUnknown => 'platforms.unknown'.tr();

  // ==================== PLATFORM LOGIN ====================

  static String platformLoginTitle(String platform) =>
      'platformLogin.title'.tr(namedArgs: {'platform': platform});
  static String get platformLoginLoading => 'platformLogin.loading'.tr();
  static String platformLoginSuccess(String platform) =>
      'platformLogin.success'.tr(namedArgs: {'platform': platform});
  static String get platformLoginFailed => 'platformLogin.failed'.tr();
  static String get platformLoginError => 'platformLogin.error'.tr();
  static String get platformLoginExtractingCookies =>
      'platformLogin.extractingCookies'.tr();
  static String get platformLoginCancel => 'platformLogin.cancel'.tr();
  static String get platformLoginClose => 'platformLogin.close'.tr();

  // ==================== QUALITY DIALOG ====================

  static String get qualityDialogTitle => 'qualityDialog.title'.tr();
  static String get qualityDialogAvailableQualities =>
      'qualityDialog.availableQualities'.tr();
  static String get qualityDialogCancel => 'qualityDialog.cancel'.tr();
  static String get qualityDialogQuality => 'qualityDialog.quality'.tr();
  static String get qualityDialogQualities => 'qualityDialog.qualities'.tr();
  static String get qualityDialogCarousel => 'qualityDialog.carousel'.tr();
  static String qualityDialogSelected(int count) =>
      'qualityDialog.selected'.tr(namedArgs: {'count': count.toString()});
  static String get qualityDialogSelectAll => 'qualityDialog.selectAll'.tr();
  static String get qualityDialogDeselect => 'qualityDialog.deselect'.tr();
  static String qualityDialogRememberChoice(String platform) =>
      'qualityDialog.rememberChoice'.tr(namedArgs: {'platform': platform});
  static String get qualityDialogDownload => 'qualityDialog.download'.tr();
  static String get qualityDialogSelectQuality =>
      'qualityDialog.selectQuality'.tr();
  static String qualityDialogDownloadImages(int count) =>
      'qualityDialog.downloadImages'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogDownloadVideos(int count) =>
      'qualityDialog.downloadVideos'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogDownloadMixed(int images, int videos) =>
      'qualityDialog.downloadMixed'.tr(
        namedArgs: {'images': images.toString(), 'videos': videos.toString()},
      );
  static String qualityDialogDownloadItems(int count) =>
      'qualityDialog.downloadItems'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogImagesTab(int count) =>
      'qualityDialog.imagesTab'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogVideosTab(int count) =>
      'qualityDialog.videosTab'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogCountVideo(int count) =>
      'qualityDialog.countVideo'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogCountAudio(int count) =>
      'qualityDialog.countAudio'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogCountImage(int count) =>
      'qualityDialog.countImage'.tr(namedArgs: {'count': count.toString()});
  static String qualityDialogCountSub(int count) =>
      'qualityDialog.countSub'.tr(namedArgs: {'count': count.toString()});

  // ==================== CONFIG DIALOG ====================

  static String get configDialogTitle => 'configDialog.title'.tr();
  static String get configDialogFileType => 'configDialog.fileType'.tr();
  static String get configDialogQuality => 'configDialog.quality'.tr();
  static String get configDialogDownloadLocation =>
      'configDialog.downloadLocation'.tr();
  static String get configDialogChangeFolder =>
      'configDialog.changeFolder'.tr();
  static String get configDialogSelectedFolder =>
      'configDialog.selectedFolder'.tr();
  static String get configDialogFreeSpace => 'configDialog.freeSpace'.tr();
  static String get configDialogFreeSpaceUnknown =>
      'configDialog.freeSpaceUnknown'.tr();
  static String get configDialogEstimatedSize =>
      'configDialog.estimatedSize'.tr();
  static String get configDialogAdvancedOptions =>
      'configDialog.advancedOptions'.tr();
  static String get configDialogAdvancedSummary =>
      'configDialog.advancedSummary'.tr();
  static String get configDialogTechnicalStreams =>
      'configDialog.technicalStreams'.tr();
  static String get configDialogTechnicalStreamsSummary =>
      'configDialog.technicalStreamsSummary'.tr();
  static String get configDialogSafeUseNote => 'configDialog.safeUseNote'.tr();
  static String get configDialogRecommended => 'configDialog.recommended'.tr();
  static String get configDialogBestAvailable =>
      'configDialog.bestAvailable'.tr();
  static String get configDialogChooseQuality =>
      'configDialog.chooseQuality'.tr();
  static String get configDialogChooseQualityHint =>
      'configDialog.chooseQualityHint'.tr();
  static String get configDialogMore => 'configDialog.more'.tr();
  static String get configDialogVideo => 'configDialog.video'.tr();
  static String get configDialogAudio => 'configDialog.audio'.tr();
  static String get configDialogImage => 'configDialog.image'.tr();
  static String get configDialogSubtitle => 'configDialog.subtitle'.tr();
  static String get configDialogVideoHint => 'configDialog.videoHint'.tr();
  static String get configDialogAudioHint => 'configDialog.audioHint'.tr();
  static String get configDialogImageHint => 'configDialog.imageHint'.tr();
  static String get configDialogSubtitleHint =>
      'configDialog.subtitleHint'.tr();
  static String get configDialogSectionFormat =>
      'configDialog.sectionFormat'.tr();
  static String get configDialogSectionExtras =>
      'configDialog.sectionExtras'.tr();
  static String get configDialogSectionSubtitles =>
      'configDialog.sectionSubtitles'.tr();
  static String get configDialogSectionSponsorBlock =>
      'configDialog.sectionSponsorBlock'.tr();
  static String get configDialogSectionPlatform =>
      'configDialog.sectionPlatform'.tr();
  static String get configDialogVideoQuality =>
      'configDialog.videoQuality'.tr();
  static String get configDialogAudioFormat => 'configDialog.audioFormat'.tr();
  static String get configDialogVideoFormat => 'configDialog.videoFormat'.tr();
  static String get configDialogAudioLosslessLabel =>
      'configDialog.audioLosslessLabel'.tr();
  static String get configDialogAudioLosslessSubtitle =>
      'configDialog.audioLosslessSubtitle'.tr();
  static String configDialogAudioQualityLossless(String format) =>
      'configDialog.audioQualityLossless'.tr(namedArgs: {'format': format});
  static String configDialogAudioQualityBitrate(String format, int bitrate) =>
      'configDialog.audioQualityBitrate'.tr(
        namedArgs: {'format': format, 'bitrate': bitrate.toString()},
      );
  static String get configDialogAudioSizeLossless =>
      'configDialog.audioSizeLossless'.tr();
  static String get configDialogAudioBitrateHighest =>
      'configDialog.audioBitrateHighest'.tr();
  static String get configDialogAudioBitrateHigh =>
      'configDialog.audioBitrateHigh'.tr();
  static String get configDialogAudioBitrateBalanced =>
      'configDialog.audioBitrateBalanced'.tr();
  static String get configDialogAudioBitrateSmaller =>
      'configDialog.audioBitrateSmaller'.tr();
  static String get configDialogAudioBitrateLowest =>
      'configDialog.audioBitrateLowest'.tr();
  static String configDialogAudioQualitySimple(String format) =>
      'configDialog.audioQualitySimple'.tr(namedArgs: {'format': format});
  static String get configDialogAudioDescMp3 =>
      'configDialog.audioDescMp3'.tr();
  static String get configDialogAudioDescM4a =>
      'configDialog.audioDescM4a'.tr();
  static String get configDialogAudioDescOpus =>
      'configDialog.audioDescOpus'.tr();
  static String get configDialogAudioDescWav =>
      'configDialog.audioDescWav'.tr();
  static String get configDialogImageQuality =>
      'configDialog.imageQuality'.tr();
  static String get configDialogRequiresFFmpeg =>
      'configDialog.requiresFFmpeg'.tr();
  static String configDialogChapters(int count) =>
      'configDialog.chapters'.tr(namedArgs: {'count': count.toString()});
  static String get configDialogChaptersSection =>
      'configDialog.chaptersSection'.tr();
  static String get configDialogLive => 'configDialog.live'.tr();
  static String configDialogViewsMillions(String count) =>
      'configDialog.viewsMillions'.tr(namedArgs: {'count': count});
  static String configDialogViewsThousands(String count) =>
      'configDialog.viewsThousands'.tr(namedArgs: {'count': count});
  static String configDialogViewsCount(int count) =>
      'configDialog.viewsCount'.tr(namedArgs: {'count': count.toString()});
  static String get configDialogEmbedThumbnail =>
      'configDialog.embedThumbnail'.tr();
  static String get configDialogEmbedMetadata =>
      'configDialog.embedMetadata'.tr();
  static String get configDialogEmbedChapters =>
      'configDialog.embedChapters'.tr();
  static String get configDialogDownloadSubtitles =>
      'configDialog.downloadSubtitles'.tr();
  static String get configDialogSubtitleOriginal =>
      'configDialog.subtitleOriginal'.tr();
  static String get configDialogSubtitleAutoTranslated =>
      'configDialog.subtitleAutoTranslated'.tr();
  static String get configDialogIncludeAutoTranslated =>
      'configDialog.includeAutoTranslated'.tr();
  static String get configDialogIncludeAutoGeneratedCaptions =>
      'configDialog.includeAutoGeneratedCaptions'.tr();
  static String get configDialogAutoGeneratedCaptions =>
      'configDialog.autoGeneratedCaptions'.tr();
  static String get configDialogSubtitleLanguages =>
      'configDialog.subtitleLanguages'.tr();
  static String get configDialogSubtitleFormat =>
      'configDialog.subtitleFormat'.tr();
  static String get configDialogSubtitleMultiHint =>
      'configDialog.subtitleMultiHint'.tr();
  static String get configDialogSubtitleFallbackHint =>
      'configDialog.subtitleFallbackHint'.tr();
  static String get configDialogSubtitleNone =>
      'configDialog.subtitleNone'.tr();
  static String get configDialogHighResMkvNote =>
      'configDialog.highResMkvNote'.tr();
  static String get configDialogSubtitleShowAll =>
      'configDialog.subtitleShowAll'.tr();
  static String get configDialogSubtitleShowLess =>
      'configDialog.subtitleShowLess'.tr();
  static String get configDialogSubtitleSelectedCount =>
      'configDialog.subtitleSelectedCount'.tr();
  static String get configDialogEnableSponsorBlock =>
      'configDialog.enableSponsorBlock'.tr();
  static String get configDialogSponsorBlockAction =>
      'configDialog.sponsorBlockAction'.tr();
  static String get configDialogSponsorBlockCategories =>
      'configDialog.sponsorBlockCategories'.tr();
  static String get configDialogRemoveTiktokWatermark =>
      'configDialog.removeTiktokWatermark'.tr();
  static String get configDialogSaveAsDefault =>
      'configDialog.saveAsDefault'.tr();
  static String get configDialogSaveAsDefaultSubtitle =>
      'configDialog.saveAsDefaultSubtitle'.tr();
  static String configDialogApplyToAll(int count) =>
      'configDialog.applyToAll'.tr(namedArgs: {'count': count.toString()});
  static String get configDialogApplyToAllConfirmTitle =>
      'configDialog.applyToAllConfirmTitle'.tr();
  static String configDialogApplyToAllConfirmBody(int count) =>
      'configDialog.applyToAllConfirmBody'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get configDialogApplyToAllConfirmAction =>
      'configDialog.applyToAllConfirmAction'.tr();
  static String get configDialogSectionTimeRange =>
      'configDialog.sectionTimeRange'.tr();
  static String get configDialogDownloadSection =>
      'configDialog.sectionDownloadSection'.tr();
  static String get configDialogSectionRequiresFFmpeg =>
      'configDialog.sectionRequiresFFmpeg'.tr();
  static String get configDialogSectionStart =>
      'configDialog.sectionStart'.tr();
  static String get configDialogSectionEnd => 'configDialog.sectionEnd'.tr();
  static String configDialogSectionSelected(String duration, String total) =>
      'configDialog.sectionSelected'.tr(
        namedArgs: {'duration': duration, 'total': total},
      );
  static String get configDialogSectionSelectChapter =>
      'configDialog.sectionSelectChapter'.tr();

  // ── Download Options dialog (formerly missionBriefing — voice rewritten) ──
  static String get downloadOptionsTitle => 'downloadOptions.title'.tr();
  static String get downloadOptionsQuality => 'downloadOptions.quality'.tr();
  static String get downloadOptionsSettings => 'downloadOptions.settings'.tr();
  static String get downloadOptionsCancel => 'downloadOptions.cancel'.tr();
  static String get downloadOptionsStart => 'downloadOptions.start'.tr();
  static String get downloadOptionsRememberChoice =>
      'downloadOptions.rememberChoice'.tr();

  /// Platform-scoped variant: "Save as default for YouTube".
  /// Pass an empty string to get the generic fallback.
  static String downloadOptionsRememberChoiceFor(String platform) {
    if (platform.isEmpty) return 'downloadOptions.rememberChoice'.tr();
    return 'downloadOptions.rememberChoiceFor'.tr(
      namedArgs: {'platform': platform},
    );
  }

  static String get downloadOptionsVideoOnly =>
      'downloadOptions.videoOnly'.tr();
  // Quality descriptors used as card subtitles
  static String get downloadOptionsDesc4K => 'downloadOptions.desc4K'.tr();
  static String get downloadOptionsDescQHD => 'downloadOptions.descQHD'.tr();
  static String get downloadOptionsDescFHD => 'downloadOptions.descFHD'.tr();
  static String get downloadOptionsDescHD => 'downloadOptions.descHD'.tr();
  static String get downloadOptionsDescSD => 'downloadOptions.descSD'.tr();
  static String get downloadOptionsDescAudio =>
      'downloadOptions.descAudio'.tr();
  static String get downloadOptionsDescVideoOnly =>
      'downloadOptions.descVideoOnly'.tr();
  static String get downloadOptionsDescSubtitle =>
      'downloadOptions.descSubtitle'.tr();

  // ==================== RIGHT PANEL (state cards in home v2) ====================
  static String get rightPanelPendingTitle => 'rightPanel.pendingTitle'.tr();
  static String rightPanelDownloadingTitle(int percent) =>
      'rightPanel.downloadingTitle'.tr(namedArgs: {'percent': '$percent'});
  static String rightPanelPausedTitle(int percent) =>
      'rightPanel.pausedTitle'.tr(namedArgs: {'percent': '$percent'});
  static String get rightPanelPausedSubtitle =>
      'rightPanel.pausedSubtitle'.tr();
  static String get rightPanelFailedTitle => 'rightPanel.failedTitle'.tr();
  static String get rightPanelCancelledTitle =>
      'rightPanel.cancelledTitle'.tr();
  static String get rightPanelCancelledSubtitle =>
      'rightPanel.cancelledSubtitle'.tr();
  static String get rightPanelWaitingNetworkTitle =>
      'rightPanel.waitingNetworkTitle'.tr();
  static String get rightPanelFileMissingTitle =>
      'rightPanel.fileMissingTitle'.tr();
  static String get rightPanelImageFileMissingTitle =>
      'rightPanel.imageFileMissingTitle'.tr();
  static String get rightPanelUnsupportedTitle =>
      'rightPanel.unsupportedTitle'.tr();
  static String get rightPanelNoEmbedTitle => 'rightPanel.noEmbedTitle'.tr();
  static String get rightPanelActionRemoveFromList =>
      'rightPanel.actionRemoveFromList'.tr();
  static String get rightPanelActionFullscreen =>
      'rightPanel.actionFullscreen'.tr();
  static String get rightPanelTooltipSpeed => 'rightPanel.tooltipSpeed'.tr();
  static String get rightPanelTooltipFullscreen =>
      'rightPanel.tooltipFullscreen'.tr();
  static String get rightPanelPendingSubtitle =>
      'rightPanel.pendingSubtitle'.tr();
  static String get rightPanelDownloadingPreparingSource =>
      'rightPanel.downloadingPreparingSource'.tr();
  static String get rightPanelFailedDefaultHint =>
      'rightPanel.failedDefaultHint'.tr();
  static String get rightPanelWaitingNetworkSubtitle =>
      'rightPanel.waitingNetworkSubtitle'.tr();
  static String get rightPanelFileMissingSubtitle =>
      'rightPanel.fileMissingSubtitle'.tr();
  static String get rightPanelNoEmbedSubtitle =>
      'rightPanel.noEmbedSubtitle'.tr();
  static String get rightPanelQuickStart => 'rightPanel.quickStart'.tr();
  static String get rightPanelQuickWebsites => 'rightPanel.quickWebsites'.tr();
  static String get rightPanelMoreSites => 'rightPanel.moreSites'.tr();
  static String get rightPanelStepPasteTitle =>
      'rightPanel.stepPasteTitle'.tr();
  static String get rightPanelStepPasteBody => 'rightPanel.stepPasteBody'.tr();
  static String get rightPanelStepChooseTitle =>
      'rightPanel.stepChooseTitle'.tr();
  static String get rightPanelStepChooseBody =>
      'rightPanel.stepChooseBody'.tr();
  static String get rightPanelStepDownloadTitle =>
      'rightPanel.stepDownloadTitle'.tr();
  static String get rightPanelStepDownloadBody =>
      'rightPanel.stepDownloadBody'.tr();
  static String get rightPanelQuickTip => 'rightPanel.quickTip'.tr();

  // ==================== HOME — additional preset/snackbar/tooltip ====================
  static String get homePresetCreateProfile => 'home.preset.createProfile'.tr();
  static String get homePresetFallbackLabel => 'home.preset.fallbackLabel'.tr();
  static String get homePresetChangeAction => 'home.preset.changeAction'.tr();
  static String get homePresetFormatVideoLabel =>
      'home.preset.formatVideoLabel'.tr();
  static String get homePresetQualityValueDefault =>
      'home.preset.qualityValueDefault'.tr();
  static String get homeCheckingPremiumLicense =>
      'home.checkingPremiumLicense'.tr();
  static String homePreparingBatch(int count) =>
      'home.preparingBatch'.tr(namedArgs: {'count': '$count'});
  static String homeStartingBatchProgress(int done, int total) =>
      'home.startingBatchProgress'.tr(
        namedArgs: {'done': '$done', 'total': '$total'},
      );
  static String get homeBatchButtonTooltip => 'home.batchButtonTooltip'.tr();
  static String get homeDownloadOptionsTip =>
      'home.downloadOptionsTip'.tr();
  static String get homeDownloadDefaultsLabel =>
      'home.downloadDefaultsLabel'.tr();
  static String get homeCustomizeBeforeDownload =>
      'home.customizeBeforeDownload'.tr();
  static String downloadsFileOpened(String filename) =>
      'downloads.fileOpened'.tr(namedArgs: {'filename': filename});
  static String downloadsFailedToOpenLocation(String error) =>
      'downloads.failedToOpenLocation'.tr(namedArgs: {'error': error});
  static String downloadsFailedToCopyUrl(String error) =>
      'downloads.failedToCopyUrl'.tr(namedArgs: {'error': error});
  static String get downloadsViewImagesTooltip =>
      'downloads.viewImagesTooltip'.tr();
  static String configDialogQualityFallbackWarning(
    String requested,
    String resolved,
  ) => 'configDialog.qualityFallbackWarning'.tr(
    namedArgs: {
      'requested': requested,
      'resolved': resolved,
      'appName': BrandConfig.current.appName,
    },
  );
  static String configDialogContainerChangedWarning(
    String requested,
    String resolved,
  ) => 'configDialog.containerChangedWarning'.tr(
    namedArgs: {
      'requested': requested,
      'resolved': resolved,
      'appName': BrandConfig.current.appName,
    },
  );
  static String get configDialogBestAvailableAuthRequired =>
      'configDialog.bestAvailableAuthRequired'.tr();

  // ==================== SETTINGS ====================

  static String get settingsTitle => 'settings.title'.tr();
  static String get settingsSearchHint => 'settingsSearch.hint'.tr();
  static String get settingsSearchNoResults => 'settingsSearch.noResults'.tr();
  static String get settingsDownloadSettings =>
      'settings.downloadSettings'.tr();
  static String get settingsDownloadLocation =>
      'settings.downloadLocation'.tr();
  static String get settingsConcurrentDownloads =>
      'settings.concurrentDownloads'.tr();
  static String settingsConcurrentDownloadsSubtitle(int count) =>
      'settings.concurrentDownloadsSubtitle'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get settingsAutoStartDownloads =>
      'settings.autoStartDownloads'.tr();
  static String get settingsAutoStartDownloadsSubtitle =>
      'settings.autoStartDownloadsSubtitle'.tr();
  static String get settingsAutoClipboardDetection =>
      'settings.autoClipboardDetection'.tr();
  static String get settingsAutoClipboardDetectionSubtitle =>
      'settings.autoClipboardDetectionSubtitle'.tr();
  static String get settingsAppearance => 'settings.appearance'.tr();
  static String get settingsTheme => 'settings.theme'.tr();
  static String get settingsThemeLight => 'settings.themeLight'.tr();
  static String get settingsThemeDark => 'settings.themeDark'.tr();
  static String get settingsThemeSystem => 'settings.themeSystem'.tr();
  static String get settingsLanguage => 'settings.language'.tr();
  static String get settingsSelectLanguageTitle =>
      'settings.selectLanguageTitle'.tr();
  static String get settingsLanguageEnglish => 'settings.languageEnglish'.tr();
  static String get settingsLanguageVietnamese =>
      'settings.languageVietnamese'.tr();
  static String get settingsNotifications => 'settings.notifications'.tr();
  static String get settingsEnableNotifications =>
      'settings.enableNotifications'.tr();
  static String get settingsEnableNotificationsSubtitle =>
      'settings.enableNotificationsSubtitle'.tr();
  static String get settingsNotificationsDisabledOS =>
      'settings.notificationsDisabledOS'.tr();
  static String get settingsNotificationsOpenSettings =>
      'settings.notificationsOpenSettings'.tr();
  static String get settingsResetToDefaults => 'settings.resetToDefaults'.tr();
  static String get settingsResetDialogTitle =>
      'settings.resetDialogTitle'.tr();
  static String get settingsResetDialogMessage =>
      'settings.resetDialogMessage'.tr();
  static String get settingsResetDialogConfirm =>
      'settings.resetDialogConfirm'.tr();
  static String get settingsResetSuccess => 'settings.resetSuccess'.tr();
  static String get settingsSelectThemeTitle =>
      'settings.selectThemeTitle'.tr();
  static String get settingsConcurrentDownloadsTitle =>
      'settings.concurrentDownloadsTitle'.tr();
  static String get settingsConcurrentDownloadsMessage =>
      'settings.concurrentDownloadsMessage'.tr();
  static String settingsConcurrentDownloadsCount(int count) {
    final key =
        count > 1
            ? 'settings.concurrentDownloadsCount_plural'
            : 'settings.concurrentDownloadsCount';
    return key.tr(namedArgs: {'count': count.toString()});
  }

  static String get settingsPlatformPreferences =>
      'settings.platformPreferences'.tr();
  static String get settingsNoPlatformPreferences =>
      'settings.noPlatformPreferences'.tr();
  static String get settingsRemovePreference =>
      'settings.removePreference'.tr();
  static String get settingsClearAllPreferences =>
      'settings.clearAllPreferences'.tr();
  static String get settingsRemovePreferenceTitle =>
      'settings.removePreferenceTitle'.tr();
  static String settingsRemovePreferenceMessage(String platform) =>
      'settings.removePreferenceMessage'.tr(namedArgs: {'platform': platform});
  static String get settingsRemove => 'settings.remove'.tr();
  static String settingsRemovedPreference(String platform) =>
      'settings.removedPreference'.tr(namedArgs: {'platform': platform});
  static String get settingsClearAllPreferencesTitle =>
      'settings.clearAllPreferencesTitle'.tr();
  static String settingsClearAllPreferencesMessage(int count) =>
      'settings.clearAllPreferencesMessage'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get settingsClearAll => 'settings.clearAll'.tr();
  static String get settingsClearedAllPreferences =>
      'settings.clearedAllPreferences'.tr();
  static String get settingsPlatformLogins => 'settings.platformLogins'.tr();
  static String get settingsNoPlatformLogins =>
      'settings.noPlatformLogins'.tr();
  static String get settingsRemoveLogin => 'settings.removeLogin'.tr();
  static String get settingsClearAllLogins => 'settings.clearAllLogins'.tr();
  static String get settingsRemoveLoginTitle =>
      'settings.removeLoginTitle'.tr();
  static String settingsRemoveLoginMessage(String platform) =>
      'settings.removeLoginMessage'.tr(namedArgs: {'platform': platform});
  static String settingsRemovedLogin(String platform) =>
      'settings.removedLogin'.tr(namedArgs: {'platform': platform});
  static String get settingsClearAllLoginsTitle =>
      'settings.clearAllLoginsTitle'.tr();
  static String settingsClearAllLoginsMessage(int count) =>
      'settings.clearAllLoginsMessage'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get settingsClearedAllLogins =>
      'settings.clearedAllLogins'.tr();
  static String settingsLoggedInOn(String date) =>
      'settings.loggedInOn'.tr(namedArgs: {'date': date});
  static String settingsErrorLoadingLogins(String error) =>
      'settings.errorLoadingLogins'.tr(namedArgs: {'error': error});

  // Browser Cookie Import
  static String get cookieImportTitle => 'settings.cookieImportTitle'.tr();
  static String get cookieImportDescription =>
      'settings.cookieImportDescription'.tr(namedArgs: _brandArgs);
  static String get cookieImportBrowser => 'settings.cookieImportBrowser'.tr();
  static String get cookieImportNone => 'settings.cookieImportNone'.tr();
  static String get cookieImportNoBrowsers =>
      'settings.cookieImportNoBrowsers'.tr();
  static String cookieImportActive(String browser) =>
      'settings.cookieImportActive'.tr(namedArgs: {'browser': browser});

  static String get settingsDownloadEngine => 'settings.downloadEngine'.tr();
  static String get settingsFormatPreferences =>
      'settings.formatPreferences'.tr();
  static String get settingsApiFallback => 'settings.apiFallback'.tr();
  static String get settingsApiFallbackSubtitle =>
      'settings.apiFallbackSubtitle'.tr();
  static String get settingsAutoUpdateBinaries =>
      'settings.autoUpdateBinaries'.tr();
  static String get settingsAutoUpdateBinariesSubtitle =>
      'settings.autoUpdateBinariesSubtitle'.tr();
  static String get settingsShowDownloadMethod =>
      'settings.showDownloadMethod'.tr();
  static String get settingsShowDownloadMethodSubtitle =>
      'settings.showDownloadMethodSubtitle'.tr();
  static String get settingsBinaryComponents =>
      'settings.binaryComponents'.tr();
  static String get settingsBinaryNotInstalled =>
      'settings.binaryNotInstalled'.tr();
  static String get settingsBinaryChecking => 'settings.binaryChecking'.tr();
  static String get settingsBinaryErrorChecking =>
      'settings.binaryErrorChecking'.tr();
  static String get settingsUpdateYtdlp => 'settings.updateYtdlp'.tr();
  static String get settingsUpdateFFmpeg => 'settings.updateFFmpeg'.tr();
  static String get settingsUpdateAll => 'settings.updateAll'.tr();
  static String get settingsSelectEngineTitle =>
      'settings.selectEngineTitle'.tr();
  static String get settingsVideoCodec => 'settings.videoCodec'.tr();
  static String get settingsAudioCodec => 'settings.audioCodec'.tr();
  static String get settingsContainerFormat => 'settings.containerFormat'.tr();
  static String get settingsFrameRate => 'settings.frameRate'.tr();
  static String get settingsMaxResolution => 'settings.maxResolution'.tr();
  static String get settingsFormatInfo => 'settings.formatInfo'.tr();
  static String get settingsUnlimited => 'settings.unlimited'.tr();
  static String get settingsVideoCodecTitle => 'settings.videoCodecTitle'.tr();
  static String get settingsAudioCodecTitle => 'settings.audioCodecTitle'.tr();
  static String get settingsContainerFormatTitle =>
      'settings.containerFormatTitle'.tr();
  static String get settingsVideoCodecHelp =>
      'settingsCodecHelp.videoCodec'.tr();
  static String get settingsAudioCodecHelp =>
      'settingsCodecHelp.audioCodec'.tr();
  static String get settingsContainerFormatHelp =>
      'settingsCodecHelp.containerFormat'.tr();
  static String get settingsFrameRateTitle => 'settings.frameRateTitle'.tr();
  static String get settingsMaxResolutionTitle =>
      'settings.maxResolutionTitle'.tr();
  static String get settingsResolution4K => 'settings.resolution4K'.tr();
  static String get settingsResolution4KDesc =>
      'settings.resolution4KDesc'.tr();
  static String get settingsResolution2K => 'settings.resolution2K'.tr();
  static String get settingsResolution2KDesc =>
      'settings.resolution2KDesc'.tr();
  static String get settingsResolution1080p => 'settings.resolution1080p'.tr();
  static String get settingsResolution1080pDesc =>
      'settings.resolution1080pDesc'.tr();
  static String get settingsResolution720p => 'settings.resolution720p'.tr();
  static String get settingsResolution720pDesc =>
      'settings.resolution720pDesc'.tr();
  static String get settingsResolution480p => 'settings.resolution480p'.tr();
  static String get settingsResolution480pDesc =>
      'settings.resolution480pDesc'.tr();
  static String get settingsResolution360p => 'settings.resolution360p'.tr();
  static String get settingsResolution360pDesc =>
      'settings.resolution360pDesc'.tr();
  static String get settingsUpdateYtdlpDialogTitle =>
      'settings.updateYtdlpDialogTitle'.tr();
  static String get settingsUpdateYtdlpDialogMessage =>
      'settings.updateYtdlpDialogMessage'.tr();
  static String get settingsUpdate => 'settings.update'.tr();
  static String get settingsUpdatingYtdlp => 'settings.updatingYtdlp'.tr();
  static String get settingsYtdlpSuccess => 'settings.ytdlpSuccess'.tr();
  static String get settingsYtdlpFailed => 'settings.ytdlpFailed'.tr();
  static String get settingsUpdatingFFmpeg => 'settings.updatingFFmpeg'.tr();
  static String get settingsFFmpegSuccess => 'settings.ffmpegSuccess'.tr();
  static String get settingsFFmpegFailed => 'settings.ffmpegFailed'.tr();
  static String get settingsUpdatingAll => 'settings.updatingAll'.tr();
  static String settingsUpdatesSummary(int success, int total) =>
      'settings.updatesSummary'.tr(
        namedArgs: {'success': success.toString(), 'total': total.toString()},
      );
  static String settingsUpdateError(String error) =>
      'settings.updateError'.tr(namedArgs: {'error': error});
  static String settingsErrorClearingLogins(String error) =>
      'settings.errorClearingLogins'.tr(namedArgs: {'error': error});

  // ==================== COMMON ====================

  static String get commonOk => 'common.ok'.tr();
  static String get commonCancel => 'common.cancel'.tr();
  static String get commonConfirm => 'common.confirm'.tr();
  static String get commonSave => 'common.save'.tr();
  static String get commonClose => 'common.close'.tr();
  static String get commonDelete => 'common.delete'.tr();
  static String get commonEdit => 'common.edit'.tr();
  static String get commonSearch => 'common.search'.tr();
  static String get commonLoading => 'common.loading'.tr();
  static String get commonError => 'common.error'.tr();
  static String get commonSuccess => 'common.success'.tr();
  static String get commonWarning => 'common.warning'.tr();
  static String get commonInfo => 'common.info'.tr();
  static String get commonClear => 'common.clear'.tr();
  static String get commonClearAll => 'common.clearAll'.tr();
  static String get commonMore => 'common.more'.tr();
  static String get commonRetry => 'common.retry'.tr();
  static String get commonBack => 'common.back'.tr();

  // ==================== ERRORS ====================

  static String errorNetwork(String message) =>
      'errors.network'.tr(namedArgs: {'message': message});
  static String errorNetworkWithCode(int code, String message) =>
      'errors.networkWithCode'.tr(
        namedArgs: {'code': code.toString(), 'message': message},
      );
  static String errorDownload(String message) =>
      'errors.download'.tr(namedArgs: {'message': message});
  static String errorStorage(String message) =>
      'errors.storage'.tr(namedArgs: {'message': message});
  static String errorPermission(String message) =>
      'errors.permission'.tr(namedArgs: {'message': message});
  static String errorValidation(String message) =>
      'errors.validation'.tr(namedArgs: {'message': message});
  static String errorUnknown(String message) =>
      'errors.unknown'.tr(namedArgs: {'message': message});
  static String errorNative(String message) =>
      'errors.native'.tr(namedArgs: {'message': message});
  static String get errorTimeout => 'errors.timeout'.tr();
  static String get errorNoInternet => 'errors.noInternet'.tr();
  static String get errorServer => 'errors.serverError'.tr();
  static String get errorUnexpected => 'errors.unexpectedError'.tr();
  static String get errorWidgetTitle => 'errors.widgetTitle'.tr();
  static String get errorWidgetSubtitle => 'errors.widgetSubtitle'.tr();
  static String get errorWidgetCopyDetails => 'errors.copyDetails'.tr();
  static String get errorWidgetDetailsCopied => 'errors.detailsCopied'.tr();
  static String get errorWidgetSendFeedback => 'errors.sendFeedback'.tr();
  static String get errorWidgetFeedbackSent => 'errors.feedbackSent'.tr();

  // ==================== DOWNLOAD PATH ====================
  static String get downloadPathPermissionError =>
      'downloadPath.permissionError'.tr();
  static String downloadPathFolderCreated(String path) =>
      'downloadPath.folderCreated'.tr(namedArgs: {'path': path});

  // ==================== SMART QUEUE ====================
  static String get smartQueueBoostedLabel => 'smartQueue.boostedLabel'.tr();
  static String get smartQueueBoostedTooltip =>
      'smartQueue.boostedTooltip'.tr();
  static String get smartQueuePriorityHigh => 'smartQueue.priorityHigh'.tr();
  static String get smartQueuePriorityLow => 'smartQueue.priorityLow'.tr();
  static String get smartQueuePriorityNormal =>
      'smartQueue.priorityNormal'.tr();
  static String get smartQueueSetPriority => 'smartQueue.setPriority'.tr();
  static String get smartQueuePriorityHighLabel =>
      'smartQueue.priorityHighLabel'.tr();
  static String get smartQueuePriorityNormalLabel =>
      'smartQueue.priorityNormalLabel'.tr();
  static String get smartQueuePriorityLowLabel =>
      'smartQueue.priorityLowLabel'.tr();
  static String get smartQueueNetworkAwareReorder =>
      'smartQueue.networkAwareReorder'.tr();
  static String get smartQueueNetworkAwareReorderSubtitle =>
      'smartQueue.networkAwareReorderSubtitle'.tr();

  // ==================== DOWNLOADS VIEW ====================

  static String get downloadsViewSwitchToGrid =>
      'downloadsView.switchToGrid'.tr();
  static String get downloadsViewSwitchToList =>
      'downloadsView.switchToList'.tr();

  // ==================== CONTEXT MENU ====================

  static String contextMenuLabel(String action) =>
      (action.contains('.') ? action : 'contextMenu.$action').tr();
  static String get contextMenuCopiedFilePath =>
      'contextMenu.copiedFilePath'.tr();

  // ==================== ERROR FEEDBACK ====================

  static String get errorFeedbackCopied => 'errorFeedback.copied'.tr();
  static String errorFeedbackTitle(String code) =>
      'errorFeedback.title.$code'.tr();
  static String errorFeedbackHint(String code) =>
      'errorFeedback.hint.$code'.tr();

  // ==================== MESSAGES ====================

  static String get messagesDownloadStarted => 'messages.downloadStarted'.tr();
  static String messagesDownloadFailed(String error) =>
      'messages.downloadFailed'.tr(namedArgs: {'error': error});
  static String messagesExtractingVideoInfo(String url) =>
      'messages.extractingVideoInfo'.tr(namedArgs: {'url': url});
  static String messagesExtractionSuccess(String title) =>
      'messages.extractionSuccess'.tr(namedArgs: {'title': title});

  // ==================== YOUTUBE SEARCH ====================

  static String get youtubeSearchTitle => 'youtubeSearch.title'.tr();
  static String get youtubeSearchButton => 'youtubeSearch.button'.tr();
  static String get youtubeSearchSearchTitle =>
      'youtubeSearch.searchTitle'.tr();
  static String get youtubeSearchPlaceholder =>
      'youtubeSearch.searchPlaceholder'.tr();
  static String get youtubeSearchHint => 'youtubeSearch.searchHint'.tr();
  static String get youtubeSearchSearching => 'youtubeSearch.searching'.tr();
  static String get youtubeSearchFailed => 'youtubeSearch.searchFailed'.tr();
  static String get youtubeSearchNoVideos => 'youtubeSearch.noVideos'.tr();
  static String get youtubeSearchTip => 'youtubeSearch.searchTip'.tr();
  static String get youtubeSearchSuggestionMusic =>
      'youtubeSearch.suggestionMusic'.tr();
  static String get youtubeSearchSuggestionTutorials =>
      'youtubeSearch.suggestionTutorials'.tr();
  static String get youtubeSearchSuggestionGaming =>
      'youtubeSearch.suggestionGaming'.tr();
  static String get youtubeSearchSuggestionNews =>
      'youtubeSearch.suggestionNews'.tr();
  static String get youtubeSearchBack => 'youtubeSearch.back'.tr();
  static String get youtubeSearchSearch => 'youtubeSearch.search'.tr();
  static String get youtubeSearchDownload => 'youtubeSearch.download'.tr();
  static String get youtubeSearchDownloadStarted =>
      'youtubeSearch.downloadStarted'.tr();
  static String get youtubeSearchRecentSearches =>
      'youtubeSearch.recentSearches'.tr();
  static String get youtubeSearchSuggestions =>
      'youtubeSearch.suggestions'.tr();
  static String get youtubeSearchPopularSearches =>
      'youtubeSearch.popularSearches'.tr();
  static String get youtubeSearchTrendingTitle =>
      'youtubeSearch.trendingTitle'.tr();
  static String get youtubeSearchPreview => 'youtubeSearch.preview'.tr();
  static String get youtubeSearchPreparing => 'youtubeSearch.preparing'.tr();
  static String get youtubeSearchPlay => 'youtubeSearch.play'.tr();
  static String get youtubeSearchOpenFolder =>
      'youtubeSearch.openFolder'.tr();
  static String get youtubeSearchRetry => 'youtubeSearch.retry'.tr();
  static String get youtubeSearchDownloaded =>
      'youtubeSearch.downloaded'.tr();
  static String get youtubeSearchFilterSortBy =>
      'youtubeSearch.filterSortBy'.tr();
  static String get youtubeSearchFilterDuration =>
      'youtubeSearch.filterDuration'.tr();
  static String get youtubeSearchFilterUploadDate =>
      'youtubeSearch.filterUploadDate'.tr();
  static String get youtubeSearchSortRelevance =>
      'youtubeSearch.sortRelevance'.tr();
  static String get youtubeSearchSortUploadDate =>
      'youtubeSearch.sortUploadDate'.tr();
  static String get youtubeSearchSortViewCount =>
      'youtubeSearch.sortViewCount'.tr();
  static String get youtubeSearchSortRating => 'youtubeSearch.sortRating'.tr();
  static String get youtubeSearchDurationAny =>
      'youtubeSearch.durationAny'.tr();
  static String get youtubeSearchDurationShort =>
      'youtubeSearch.durationShort'.tr();
  static String get youtubeSearchDurationMedium =>
      'youtubeSearch.durationMedium'.tr();
  static String get youtubeSearchDurationLong =>
      'youtubeSearch.durationLong'.tr();
  static String get youtubeSearchUploadAnytime =>
      'youtubeSearch.uploadAnytime'.tr();
  static String get youtubeSearchUploadToday =>
      'youtubeSearch.uploadToday'.tr();
  static String get youtubeSearchUploadThisWeek =>
      'youtubeSearch.uploadThisWeek'.tr();
  static String get youtubeSearchUploadThisMonth =>
      'youtubeSearch.uploadThisMonth'.tr();
  static String get youtubeSearchUploadThisYear =>
      'youtubeSearch.uploadThisYear'.tr();
  static String get youtubeSearchSelectVideo =>
      'youtubeSearch.selectVideo'.tr();
  static String get youtubeSearchSelectVideoHint =>
      'youtubeSearch.selectVideoHint'.tr();
  static String get youtubeSearchCurrentlySelected =>
      'youtubeSearch.currentlySelected'.tr();
  static String get youtubeSearchAvailableQuality =>
      'youtubeSearch.availableQuality'.tr();
  static String get youtubeSearchAudioOnly => 'youtubeSearch.audioOnly'.tr();
  static String get youtubeSearchNoFormats => 'youtubeSearch.noFormats'.tr();
  static String get youtubeSearchQualityError =>
      'youtubeSearch.qualityError'.tr();
  static String get youtubeSearchLoadingQuality =>
      'youtubeSearch.loadingQuality'.tr();
  static String get youtubeSearchChannel => 'youtubeSearch.channel'.tr();
  static String get youtubeSearchAbout => 'youtubeSearch.about'.tr();
  static String youtubeSearchResultsCount(int count) =>
      'youtubeSearch.resultsCount'.tr(namedArgs: {'count': count.toString()});
  static String get youtubeSearchYourSubscriptions =>
      'youtubeSearch.yourSubscriptions'.tr();
  static String get youtubeSearchOpenInBrowser =>
      'youtubeSearch.openInBrowser'.tr();

  // ==================== YOUTUBE PLAYLIST ====================

  static String get youtubePlaylistTitle => 'youtubePlaylist.title'.tr();
  static String get youtubePlaylistButton => 'youtubePlaylist.button'.tr();
  static String get youtubePlaylistUrlPlaceholder =>
      'youtubePlaylist.urlPlaceholder'.tr();
  static String get youtubePlaylistLoading => 'youtubePlaylist.loading'.tr();
  static String get youtubePlaylistLoadFailed =>
      'youtubePlaylist.loadFailed'.tr();
  static String get youtubePlaylistEmptyTitle =>
      'youtubePlaylist.emptyTitle'.tr();
  static String get youtubePlaylistEmptyDescription =>
      'youtubePlaylist.emptyDescription'.tr();
  static String get youtubePlaylistSelectAll =>
      'youtubePlaylist.selectAll'.tr();
  static String get youtubePlaylistDeselectAll =>
      'youtubePlaylist.deselectAll'.tr();
  static String youtubePlaylistSelectedCount(int count) =>
      'youtubePlaylist.selectedCount'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String youtubePlaylistDownloadSelected(int count) =>
      'youtubePlaylist.downloadSelected'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String youtubePlaylistDownloadQueueMessage(int count) =>
      'youtubePlaylist.downloadQueueMessage'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get youtubePlaylistTryAgain => 'youtubePlaylist.tryAgain'.tr();

  // ==================== YOUTUBE CHANNEL ====================

  static String get youtubeChannelTitle => 'youtubeChannel.title'.tr();
  static String get youtubeChannelButton => 'youtubeChannel.button'.tr();
  static String get youtubeChannelBrowse => 'youtubeChannel.browse'.tr();
  static String get youtubeChannelUrlPlaceholder =>
      'youtubeChannel.urlPlaceholder'.tr();
  static String get youtubeChannelBrowseButton =>
      'youtubeChannel.browseButton'.tr();
  static String get youtubeChannelLoading => 'youtubeChannel.loading'.tr();
  static String get youtubeChannelLoadFailed =>
      'youtubeChannel.loadFailed'.tr();
  static String get youtubeChannelEmptyTitle =>
      'youtubeChannel.emptyTitle'.tr();
  static String get youtubeChannelEmptyDescription =>
      'youtubeChannel.emptyDescription'.tr();
  static String get youtubeChannelSearchVideos =>
      'youtubeChannel.searchVideos'.tr();
  static String get youtubeChannelSelectAll => 'youtubeChannel.selectAll'.tr();
  static String get youtubeChannelDeselectAll =>
      'youtubeChannel.deselectAll'.tr();
  static String youtubeChannelSelectedCount(int count) =>
      'youtubeChannel.selectedCount'.tr(namedArgs: {'count': count.toString()});
  static String youtubeChannelDownloadCount(int count) =>
      'youtubeChannel.downloadCount'.tr(namedArgs: {'count': count.toString()});
  static String youtubeChannelChannelInfo(String title, int count) =>
      'youtubeChannel.channelInfo'.tr(
        namedArgs: {'title': title, 'count': count.toString()},
      );
  static String youtubeChannelVideosCount(int count) =>
      'youtubeChannel.videosCount'.tr(namedArgs: {'count': count.toString()});
  static String youtubeChannelVideosQueued(int count) =>
      'youtubeChannel.videosQueued'.tr(namedArgs: {'count': count.toString()});
  static String get youtubeChannelSortTooltip =>
      'youtubeChannel.sortTooltip'.tr();
  static String get youtubeChannelSortDateNewest =>
      'youtubeChannel.sortDateNewest'.tr();
  static String get youtubeChannelSortDateOldest =>
      'youtubeChannel.sortDateOldest'.tr();
  static String get youtubeChannelSortDurationShort =>
      'youtubeChannel.sortDurationShort'.tr();
  static String get youtubeChannelSortDurationLong =>
      'youtubeChannel.sortDurationLong'.tr();
  static String get youtubeChannelSortViewsMost =>
      'youtubeChannel.sortViewsMost'.tr();
  static String get youtubeChannelSortViewsLeast =>
      'youtubeChannel.sortViewsLeast'.tr();

  // ==================== SUBSCRIPTIONS ====================

  static String get subscriptionsTitle => 'subscriptions.title'.tr();
  static String get subscriptionsButton => 'subscriptions.button'.tr();
  static String get subscriptionsCheckForNewVideos =>
      'subscriptions.checkForNewVideos'.tr();
  static String get subscriptionsEmpty => 'subscriptions.empty'.tr();
  static String get subscriptionsEmptyDescription =>
      'subscriptions.emptyDescription'.tr();
  static String get subscriptionsUrlPlaceholder =>
      'subscriptions.urlPlaceholder'.tr();
  static String get subscriptionsSearchPlaceholder =>
      'subscriptions.searchPlaceholder'.tr();
  static String subscriptionsActiveFeeds(int count) =>
      'subscriptions.activeFeeds'.tr(namedArgs: {'count': '$count'});
  static String subscriptionsFilteredFeeds(int filtered, int total) =>
      'subscriptions.filteredFeeds'.tr(
        namedArgs: {'filtered': '$filtered', 'total': '$total'},
      );
  static String subscriptionsFoundNewVideos(int count, String channels) =>
      'subscriptions.foundNewVideos'.tr(
        namedArgs: {'count': count.toString(), 'channels': channels},
      );
  static String get subscriptionsFoundNewVideosChannel =>
      'subscriptions.foundNewVideosChannel'.tr();
  static String get subscriptionsFoundNewVideosChannels =>
      'subscriptions.foundNewVideosChannels'.tr();
  static String get subscriptionsAllUpToDate =>
      'subscriptions.allUpToDate'.tr();
  static String get subscriptionsCannotOpenChannel =>
      'subscriptions.cannotOpenChannel'.tr();
  static String subscriptionsSubscribedTo(String channel) =>
      'subscriptions.subscribedTo'.tr(namedArgs: {'channel': channel});
  static String subscriptionsUnsubscribedFrom(String channel) =>
      'subscriptions.unsubscribedFrom'.tr(namedArgs: {'channel': channel});
  static String subscriptionsFailedToSubscribe(String channel) =>
      'subscriptions.failedToSubscribe'.tr(namedArgs: {'channel': channel});
  static String subscriptionsFailedToUnsubscribe(String channel) =>
      'subscriptions.failedToUnsubscribe'.tr(namedArgs: {'channel': channel});

  // ==================== VIDEO DETAIL PANEL (metadata grid) ====================

  static String get videoDetailMetaBitrate => 'videoDetail.metaBitrate'.tr();
  static String get videoDetailMetaAudio => 'videoDetail.metaAudio'.tr();
  static String get videoDetailMetaSource => 'videoDetail.metaSource'.tr();
  static String get videoDetailMetaSourceDirect =>
      'videoDetail.metaSourceDirect'.tr();
  static String get videoDetailMetaFrameRate =>
      'videoDetail.metaFrameRate'.tr();
  static String get videoDetailMetaUploaded => 'videoDetail.metaUploaded'.tr();

  // ==================== CHANNEL VIDEO LIST ====================

  static String get channelVideoListSearchHint =>
      'channelVideoList.searchHint'.tr();

  // ==================== EXTRACTION HISTORY ====================

  static String get extractionHistoryTitle => 'extractionHistory.title'.tr();
  static String extractionHistoryCacheInfo(int count) =>
      'extractionHistory.cacheInfo'.tr(namedArgs: {'count': count.toString()});
  static String get extractionHistoryClearAllTooltip =>
      'extractionHistory.clearAllTooltip'.tr();
  static String get extractionHistoryCloseTooltip =>
      'extractionHistory.closeTooltip'.tr();
  static String get extractionHistoryEmpty => 'extractionHistory.empty'.tr();
  static String get extractionHistoryEmptySubtitle =>
      'extractionHistory.emptySubtitle'.tr();
  static String get extractionHistoryClearTitle =>
      'extractionHistory.clearTitle'.tr();
  static String get extractionHistoryClearMessage =>
      'extractionHistory.clearMessage'.tr();
  static String get extractionHistoryClearConfirm =>
      'extractionHistory.clearConfirm'.tr();
  static String extractionHistoryQualities(int count) =>
      'extractionHistory.qualities'.tr(namedArgs: {'count': count.toString()});
  static String get extractionHistoryTimeJustNow =>
      'extractionHistory.timeJustNow'.tr();
  static String extractionHistoryTimeMinutesAgo(int minutes) =>
      'extractionHistory.timeMinutesAgo'.tr(
        namedArgs: {'minutes': minutes.toString()},
      );
  static String extractionHistoryTimeHoursAgo(int hours) =>
      'extractionHistory.timeHoursAgo'.tr(
        namedArgs: {'hours': hours.toString()},
      );
  static String extractionHistoryTimeDaysAgo(int days) =>
      'extractionHistory.timeDaysAgo'.tr(namedArgs: {'days': days.toString()});

  // ==================== SETTINGS SECTIONS ====================
  static String get settingsSectionGeneral => 'settingsSection.general'.tr();
  static String get settingsSectionDownloads =>
      'settingsSection.downloads'.tr();
  static String get settingsSectionQualityFormat =>
      'settingsSection.qualityFormat'.tr();
  static String get settingsSectionMediaProcessing =>
      'settingsSection.mediaProcessing'.tr();
  static String get settingsSectionPlatforms =>
      'settingsSection.platforms'.tr();
  static String get settingsSectionBrowser => 'settingsSection.browser'.tr();
  static String get settingsSectionNetworkProxy =>
      'settingsSection.networkProxy'.tr();
  static String get settingsSectionEngineComponents =>
      'settingsSection.engineComponents'.tr();
  static String get settingsSectionAboutSupport =>
      'settingsSection.aboutSupport'.tr();
  static String get settingsSectionSubtitles =>
      'settingsSection.subtitles'.tr();
  static String get settingsSectionMediaEnhancements =>
      'settingsSection.mediaEnhancements'.tr();
  static String get settingsSectionSponsorBlock =>
      'settingsSection.sponsorBlock'.tr();
  static String get settingsSectionPlatformSettings =>
      'settingsSection.platformSettings'.tr();
  static String get settingsSectionNetworkAdvanced =>
      'settingsSection.networkAdvanced'.tr();

  // ==================== VIDEO CODEC (ENUMS) ====================
  static String get settingsVideoCodecAuto => 'settingsVideoCodec.auto'.tr();
  static String get settingsVideoCodecH264 => 'settingsVideoCodec.h264'.tr();
  static String get settingsVideoCodecH265 => 'settingsVideoCodec.h265'.tr();
  static String get settingsVideoCodecVP9 => 'settingsVideoCodec.vp9'.tr();
  static String get settingsVideoCodecAV1 => 'settingsVideoCodec.av1'.tr();
  static String get settingsVideoCodecAutoDesc =>
      'settingsVideoCodec.autoDesc'.tr();
  static String get settingsVideoCodecH264Desc =>
      'settingsVideoCodec.h264Desc'.tr();
  static String get settingsVideoCodecH265Desc =>
      'settingsVideoCodec.h265Desc'.tr();
  static String get settingsVideoCodecVP9Desc =>
      'settingsVideoCodec.vp9Desc'.tr();
  static String get settingsVideoCodecAV1Desc =>
      'settingsVideoCodec.av1Desc'.tr();

  // ==================== AUDIO CODEC (ENUMS) ====================
  static String get settingsAudioCodecAuto => 'settingsAudioCodec.auto'.tr();
  static String get settingsAudioCodecAAC => 'settingsAudioCodec.aac'.tr();
  static String get settingsAudioCodecOpus => 'settingsAudioCodec.opus'.tr();
  static String get settingsAudioCodecMP3 => 'settingsAudioCodec.mp3'.tr();
  static String get settingsAudioCodecAutoDesc =>
      'settingsAudioCodec.autoDesc'.tr();
  static String get settingsAudioCodecAACDesc =>
      'settingsAudioCodec.aacDesc'.tr();
  static String get settingsAudioCodecOpusDesc =>
      'settingsAudioCodec.opusDesc'.tr();
  static String get settingsAudioCodecMP3Desc =>
      'settingsAudioCodec.mp3Desc'.tr();

  // ==================== FPS (ENUMS) ====================
  static String get settingsFpsAuto => 'settingsFps.auto'.tr();
  static String get settingsFpsPrefer60 => 'settingsFps.prefer60'.tr();
  static String get settingsFpsPrefer30 => 'settingsFps.prefer30'.tr();
  static String get settingsFpsAutoDesc => 'settingsFps.autoDesc'.tr();
  static String get settingsFpsPrefer60Desc => 'settingsFps.prefer60Desc'.tr();
  static String get settingsFpsPrefer30Desc => 'settingsFps.prefer30Desc'.tr();

  // ==================== CONTAINER (ENUMS) ====================
  static String get settingsContainerMP4 => 'settingsContainer.mp4'.tr();
  static String get settingsContainerMKV => 'settingsContainer.mkv'.tr();
  static String get settingsContainerWebM => 'settingsContainer.webm'.tr();
  static String get settingsContainerMP4Desc =>
      'settingsContainer.mp4Desc'.tr();
  static String get settingsContainerMKVDesc =>
      'settingsContainer.mkvDesc'.tr();
  static String get settingsContainerWebMDesc =>
      'settingsContainer.webmDesc'.tr();
  // Recoded containers (require --recode-video post-process).
  static String get settingsContainerAVI => 'settingsContainer.avi'.tr();
  static String get settingsContainerMOV => 'settingsContainer.mov'.tr();
  static String get settingsContainerM4V => 'settingsContainer.m4v'.tr();
  static String get settingsContainerFLV => 'settingsContainer.flv'.tr();
  static String get settingsContainerAVIDesc =>
      'settingsContainer.aviDesc'.tr();
  static String get settingsContainerMOVDesc =>
      'settingsContainer.movDesc'.tr();
  static String get settingsContainerM4VDesc =>
      'settingsContainer.m4vDesc'.tr();
  static String get settingsContainerFLVDesc =>
      'settingsContainer.flvDesc'.tr();

  // ==================== QUALITY (ENUMS) ====================
  static String get settingsQualityAuto => 'settingsQuality.auto'.tr();
  static String get settingsQualityBest => 'settingsQuality.best'.tr();
  static String get settingsQualityAudioOnly =>
      'settingsQuality.audioOnly'.tr();

  // ==================== ENGINE (ENUMS) ====================
  static String get settingsEngineAuto => 'settingsEngine.auto'.tr();
  static String get settingsEngineYtdlpOnly => 'settingsEngine.ytdlpOnly'.tr();
  static String get settingsEngineAutoDesc => 'settingsEngine.autoDesc'.tr();
  static String get settingsEngineYtdlpOnlyDesc =>
      'settingsEngine.ytdlpOnlyDesc'.tr();
  static String get settingsEngineApiOnlyDesc =>
      'settingsEngine.apiOnlyDesc'.tr();

  // ==================== BINARIES ====================
  static String get settingsBinariesAutoUpdate =>
      'settingsBinaries.autoUpdate'.tr();
  static String get settingsBinariesAutoUpdateDesc =>
      'settingsBinaries.autoUpdateDesc'.tr();
  static String get settingsBinariesAutoUpdateYtdlp =>
      'settingsBinaries.autoUpdateYtdlp'.tr();
  static String get settingsBinariesAutoUpdateYtdlpDesc =>
      'settingsBinaries.autoUpdateYtdlpDesc'.tr();
  static String get settingsBinariesShowDownloadMethod =>
      'settingsBinaries.showDownloadMethod'.tr();
  static String get settingsBinariesShowDownloadMethodDesc =>
      'settingsBinaries.showDownloadMethodDesc'.tr();
  static String get settingsBinariesChecking =>
      'settingsBinaries.checking'.tr();
  static String get settingsBinariesErrorCheckingVersion =>
      'settingsBinaries.errorCheckingVersion'.tr();
  static String get settingsBinariesUpdateAll =>
      'settingsBinaries.updateAll'.tr();
  static String get settingsBinariesSelectEngine =>
      'settingsBinaries.selectEngine'.tr();

  // ==================== API FALLBACK ====================
  static String get settingsApiFallbackTitle2 =>
      'settingsApiFallback.title'.tr();
  static String get settingsApiFallbackSubtitle2 =>
      'settingsApiFallback.subtitle'.tr();

  // ==================== SPONSORBLOCK ====================
  static String get settingsSponsorBlockCategories =>
      'settingsSponsorBlock.categories'.tr();
  static String get settingsSponsorBlockAction =>
      'settingsSponsorBlock.action'.tr();
  static String get settingsSponsorBlockActionSkip =>
      'settingsSponsorBlock.actionSkip'.tr();
  static String get settingsSponsorBlockActionRemove =>
      'settingsSponsorBlock.actionRemove'.tr();
  static String get settingsSponsorBlockActionChapter =>
      'settingsSponsorBlock.actionChapter'.tr();
  static String get settingsSponsorBlockCategorySponsor =>
      'settingsSponsorBlock.categorySponsor'.tr();
  static String get settingsSponsorBlockCategorySelfpromo =>
      'settingsSponsorBlock.categorySelfpromo'.tr();
  static String get settingsSponsorBlockCategoryInteraction =>
      'settingsSponsorBlock.categoryInteraction'.tr();
  static String get settingsSponsorBlockCategoryIntro =>
      'settingsSponsorBlock.categoryIntro'.tr();
  static String get settingsSponsorBlockCategoryOutro =>
      'settingsSponsorBlock.categoryOutro'.tr();
  static String get settingsSponsorBlockCategoryPreview =>
      'settingsSponsorBlock.categoryPreview'.tr();
  static String get settingsSponsorBlockCategoryMusic =>
      'settingsSponsorBlock.categoryMusic'.tr();
  static String get settingsSponsorBlockCategoryFiller =>
      'settingsSponsorBlock.categoryFiller'.tr();

  // SponsorBlock — config-dialog helpers (section hint + category tooltips)
  static String get configDialogSponsorBlockHint =>
      'configDialog.sponsorBlockHint'.tr();
  static String get sponsorBlockCategoryDescSponsor =>
      'settingsSponsorBlock.descSponsor'.tr();
  static String get sponsorBlockCategoryDescSelfpromo =>
      'settingsSponsorBlock.descSelfpromo'.tr();
  static String get sponsorBlockCategoryDescInteraction =>
      'settingsSponsorBlock.descInteraction'.tr();
  static String get sponsorBlockCategoryDescIntro =>
      'settingsSponsorBlock.descIntro'.tr();
  static String get sponsorBlockCategoryDescOutro =>
      'settingsSponsorBlock.descOutro'.tr();
  static String get sponsorBlockCategoryDescPreview =>
      'settingsSponsorBlock.descPreview'.tr();
  static String get sponsorBlockCategoryDescMusic =>
      'settingsSponsorBlock.descMusic'.tr();
  static String get sponsorBlockCategoryDescFiller =>
      'settingsSponsorBlock.descFiller'.tr();

  // ==================== SMART HINTS ====================
  static String settingsSmartHintsResolutionUpgrade(int resolution) =>
      'settingsSmartHints.resolutionUpgrade'.tr(
        namedArgs: {'resolution': resolution.toString()},
      );
  static String get settingsSmartHintsCodecUpgrade =>
      'settingsSmartHints.codecUpgrade'.tr();

  // ==================== PLATFORM ====================
  static String get settingsPlatformOverrideSubs =>
      'settingsPlatform.overrideSubs'.tr();
  static String get settingsPlatformOverrideSB =>
      'settingsPlatform.overrideSB'.tr();
  static String settingsPlatformClearLoginsError(String error) =>
      'settingsPlatform.clearLoginsError'.tr(namedArgs: {'error': error});

  // ==================== BINARY COMPONENTS ====================
  static String get settingsBinaryComponentsTitle =>
      'settingsBinaryComponents.title'.tr();
  static String get settingsBinaryComponentsYtdlp =>
      'settingsBinaryComponents.ytdlp'.tr();
  static String get settingsBinaryComponentsFFmpeg =>
      'settingsBinaryComponents.ffmpeg'.tr();
  static String get settingsBinaryComponentsGalleryDl =>
      'settingsBinaryComponents.galleryDl'.tr();
  static String get settingsBinaryComponentsNotInstalled =>
      'settingsBinaryComponents.notInstalled'.tr();
  static String get settingsBinaryComponentsUpdateYtdlp =>
      'settingsBinaryComponents.updateYtdlp'.tr();
  static String get settingsBinaryComponentsUpdateFFmpeg =>
      'settingsBinaryComponents.updateFFmpeg'.tr();
  static String get settingsBinaryComponentsRepairGalleryDl =>
      'settingsBinaryComponents.repairGalleryDl'.tr();
  static String get settingsBinaryComponentsOnline =>
      'settingsBinaryComponents.online'.tr();
  static String get settingsBinaryComponentsOffline =>
      'settingsBinaryComponents.offline'.tr();
  static String get settingsBinaryComponentsUpdatingYtdlp =>
      'settingsBinaryComponents.updatingYtdlp'.tr();
  static String get settingsBinaryComponentsUpdatingFfmpeg =>
      'settingsBinaryComponents.updatingFfmpeg'.tr();
  static String get settingsBinaryComponentsUpdatingAllBinaries =>
      'settingsBinaryComponents.updatingAllBinaries'.tr();
  static String get settingsBinaryComponentsUpdateInProgress =>
      'settingsBinaryComponents.updateInProgress'.tr();
  static String settingsBinaryComponentsUpdateProgress(
    int success,
    int total,
  ) => 'settingsBinaryComponents.updateProgress'.tr(
    namedArgs: {'success': '$success', 'total': '$total'},
  );
  static String settingsBinaryComponentsRepairingBinary(String name) =>
      'settingsBinaryComponents.repairingBinary'.tr(namedArgs: {'name': name});
  static String settingsBinaryComponentsBinaryRepaired(String name) =>
      'settingsBinaryComponents.binaryRepaired'.tr(namedArgs: {'name': name});
  static String settingsBinaryComponentsBinaryRepairFailed(String name) =>
      'settingsBinaryComponents.binaryRepairFailed'.tr(
        namedArgs: {'name': name},
      );
  static String settingsBinaryComponentsPreparingBinary(String name) =>
      'settingsBinaryComponents.preparingBinary'.tr(namedArgs: {'name': name});
  static String settingsBinaryComponentsDownloadingBinary(String name) =>
      'settingsBinaryComponents.downloadingBinary'.tr(
        namedArgs: {'name': name},
      );
  static String settingsBinaryComponentsDownloadingBinaryPercent(
    String name,
    int percent,
  ) => 'settingsBinaryComponents.downloadingBinaryPercent'.tr(
    namedArgs: {'name': name, 'percent': '$percent'},
  );
  static String settingsBinaryComponentsInstallingBinary(String name) =>
      'settingsBinaryComponents.installingBinary'.tr(namedArgs: {'name': name});
  static String settingsBinaryComponentsBinaryUpdated(String name) =>
      'settingsBinaryComponents.binaryUpdated'.tr(namedArgs: {'name': name});
  static String settingsBinaryComponentsBinaryUpdateFailed(String name) =>
      'settingsBinaryComponents.binaryUpdateFailed'.tr(
        namedArgs: {'name': name},
      );

  // ==================== FORMAT PREFERENCES ====================
  static String get settingsFormatPreferencesForceRemux =>
      'settingsFormatPreferences.forceRemux'.tr();
  static String settingsFormatPreferencesForceRemuxDesc(String format) =>
      'settingsFormatPreferences.forceRemuxDesc'.tr(
        namedArgs: {'format': format},
      );
  static String get settingsFormatPreferencesInfoText =>
      'settingsFormatPreferences.infoText'.tr();
  static String get settingsFormatPreferencesUnlimitedResolution =>
      'settingsFormatPreferences.unlimitedResolution'.tr();

  // ==================== SUBTITLES ====================
  static String get settingsSubtitlesDownloadSubtitles =>
      'settingsSubtitles.downloadSubtitles'.tr();
  static String get settingsSubtitlesDownloadSubtitlesDesc =>
      'settingsSubtitles.downloadSubtitlesDesc'.tr();
  static String get settingsSubtitlesSubtitleLanguages =>
      'settingsSubtitles.subtitleLanguages'.tr();
  static String get settingsSubtitlesSubtitleFormat =>
      'settingsSubtitles.subtitleFormat'.tr();
  static String get settingsSubtitlesEmbedSubtitles =>
      'settingsSubtitles.embedSubtitles'.tr();
  static String get settingsSubtitlesEmbedSubtitlesDesc =>
      'settingsSubtitles.embedSubtitlesDesc'.tr();
  static String get settingsSubtitlesSelectLanguagesTitle =>
      'settingsSubtitles.selectLanguagesTitle'.tr();
  static String get settingsSubtitlesInfoText =>
      'settingsSubtitles.infoText'.tr();
  static String get settingsSubtitlesSave => 'settingsSubtitles.save'.tr();
  static String get settingsSubtitlesLanguageEnglish =>
      'settingsSubtitles.languageEnglish'.tr();
  static String get settingsSubtitlesLanguageVietnamese =>
      'settingsSubtitles.languageVietnamese'.tr();
  static String get settingsSubtitlesLanguageChinese =>
      'settingsSubtitles.languageChinese'.tr();
  static String get settingsSubtitlesLanguageJapanese =>
      'settingsSubtitles.languageJapanese'.tr();
  static String get settingsSubtitlesLanguageKorean =>
      'settingsSubtitles.languageKorean'.tr();
  static String get settingsSubtitlesLanguageSpanish =>
      'settingsSubtitles.languageSpanish'.tr();
  static String get settingsSubtitlesLanguageFrench =>
      'settingsSubtitles.languageFrench'.tr();
  static String get settingsSubtitlesLanguageGerman =>
      'settingsSubtitles.languageGerman'.tr();
  static String get settingsSubtitlesLanguagePortuguese =>
      'settingsSubtitles.languagePortuguese'.tr();
  static String get settingsSubtitlesLanguageRussian =>
      'settingsSubtitles.languageRussian'.tr();
  static String get settingsSubtitlesLanguageArabic =>
      'settingsSubtitles.languageArabic'.tr();
  static String get settingsSubtitlesLanguageHindi =>
      'settingsSubtitles.languageHindi'.tr();
  static String get settingsSubtitlesLanguageAuto =>
      'settingsSubtitles.languageAuto'.tr();
  static String get settingsSubtitlesLanguageAll =>
      'settingsSubtitles.languageAll'.tr();

  // ==================== MEDIA ENHANCEMENTS ====================
  static String get settingsMediaEnhancementsDownloadThumbnail =>
      'settingsMediaEnhancements.downloadThumbnail'.tr();
  static String get settingsMediaEnhancementsDownloadThumbnailDesc =>
      'settingsMediaEnhancements.downloadThumbnailDesc'.tr();
  static String get settingsMediaEnhancementsEmbedThumbnail =>
      'settingsMediaEnhancements.embedThumbnail'.tr();
  static String get settingsMediaEnhancementsEmbedThumbnailDesc =>
      'settingsMediaEnhancements.embedThumbnailDesc'.tr();
  static String get settingsMediaEnhancementsEmbedMetadata =>
      'settingsMediaEnhancements.embedMetadata'.tr();
  static String get settingsMediaEnhancementsEmbedMetadataDesc =>
      'settingsMediaEnhancements.embedMetadataDesc'.tr();
  static String get settingsMediaEnhancementsEmbedChapters =>
      'settingsMediaEnhancements.embedChapters'.tr();
  static String get settingsMediaEnhancementsEmbedChaptersDesc =>
      'settingsMediaEnhancements.embedChaptersDesc'.tr();

  // ==================== SPONSORBLOCK SECTION ====================
  static String get settingsSponsorBlockSectionEnableSponsorBlock =>
      'settingsSponsorBlockSection.enableSponsorBlock'.tr();
  static String get settingsSponsorBlockSectionEnableSponsorBlockDesc =>
      'settingsSponsorBlockSection.enableSponsorBlockDesc'.tr();
  static String get settingsSponsorBlockSectionSponsorBlockAction =>
      'settingsSponsorBlockSection.sponsorBlockAction'.tr();
  static String get settingsSponsorBlockSectionSegmentCategories =>
      'settingsSponsorBlockSection.segmentCategories'.tr();

  // ==================== PLATFORM SPECIFIC ====================
  static String get settingsPlatformSpecificRemoveTikTokWatermark =>
      'settingsPlatformSpecific.removeTikTokWatermark'.tr();
  static String get settingsPlatformSpecificRemoveTikTokWatermarkDesc =>
      'settingsPlatformSpecific.removeTikTokWatermarkDesc'.tr();

  // ==================== NETWORK & ADVANCED ====================
  static String get settingsNetworkAdvancedProxy =>
      'settingsNetworkAdvanced.proxy'.tr();
  static String get settingsNetworkAdvancedProxyConfiguration =>
      'settingsNetworkAdvanced.proxyConfiguration'.tr();
  static String get settingsNetworkAdvancedGeoBypass =>
      'settingsNetworkAdvanced.geoBypass'.tr();
  static String get settingsNetworkAdvancedGeoBypassDesc =>
      'settingsNetworkAdvanced.geoBypassDesc'.tr();
  static String get settingsNetworkAdvancedGeoBypassCountry =>
      'settingsNetworkAdvanced.geoBypassCountry'.tr();
  static String get settingsNetworkAdvancedArchiveMode =>
      'settingsNetworkAdvanced.archiveMode'.tr();
  static String get settingsNetworkAdvancedArchiveModeDesc =>
      'settingsNetworkAdvanced.archiveModeDesc'.tr();
  static String get settingsNetworkAdvancedAutoRetry =>
      'settingsNetworkAdvanced.autoRetry'.tr();
  static String get settingsNetworkAdvancedAutoRetryDesc =>
      'settingsNetworkAdvanced.autoRetryDesc'.tr();
  static String get settingsNetworkAdvancedDateAfter =>
      'settingsNetworkAdvanced.dateAfter'.tr();
  static String get settingsNetworkAdvancedDateBefore =>
      'settingsNetworkAdvanced.dateBefore'.tr();
  static String get settingsNetworkAdvancedMinimumDuration =>
      'settingsNetworkAdvanced.minimumDuration'.tr();
  static String get settingsNetworkAdvancedMaximumDuration =>
      'settingsNetworkAdvanced.maximumDuration'.tr();
  static String get settingsNetworkAdvancedClear =>
      'settingsNetworkAdvanced.clear'.tr();
  static String get settingsNetworkAdvancedSave =>
      'settingsNetworkAdvanced.save'.tr();
  static String get settingsNetworkAdvancedNotConfigured =>
      'settingsNetworkAdvanced.notConfigured'.tr();
  static String get settingsNetworkAdvancedNotSet =>
      'settingsNetworkAdvanced.notSet'.tr();
  static String get settingsNetworkAdvancedAutoDetect =>
      'settingsNetworkAdvanced.autoDetect'.tr();
  static String get settingsNetworkAdvancedSelectDate =>
      'settingsNetworkAdvanced.selectDate'.tr();
  static String get settingsNetworkAdvancedProxyPlaceholder =>
      'settingsNetworkAdvanced.proxyPlaceholder'.tr();
  static String get settingsNetworkAdvancedProxyHelper =>
      'settingsNetworkAdvanced.proxyHelper'.tr();
  static String get settingsNetworkAdvancedProxyFormats =>
      'settingsNetworkAdvanced.proxyFormats'.tr();
  static String get settingsNetworkAdvancedAutoDetectDesc =>
      'settingsNetworkAdvanced.autoDetectDesc'.tr();

  // ==================== SETTINGS MESSAGES ====================
  static String get settingsMessagesYtdlpUpdateSuccess =>
      'settingsMessages.ytdlpUpdateSuccess'.tr();
  static String get settingsMessagesYtdlpUpdateFailed =>
      'settingsMessages.ytdlpUpdateFailed'.tr();
  static String get settingsMessagesFFmpegUpdateSuccess =>
      'settingsMessages.ffmpegUpdateSuccess'.tr();
  static String get settingsMessagesFFmpegUpdateFailed =>
      'settingsMessages.ffmpegUpdateFailed'.tr();

  // ==================== SETTINGS INFO TEXTS ====================
  static String get settingsInfoTextsMediaEnhancements =>
      'settingsInfoTexts.mediaEnhancements'.tr();
  static String get settingsInfoTextsSponsorBlock =>
      'settingsInfoTexts.sponsorBlock'.tr();
  static String get settingsInfoTextsPlatformSpecific =>
      'settingsInfoTexts.platformSpecific'.tr();

  // ==================== HOME BATCH DOWNLOAD ====================
  static String get homeBatchDownloadTitle => 'homeBatchDownload.title'.tr();
  static String get homeBatchDownloadInputLabel =>
      'homeBatchDownload.inputLabel'.tr();
  static String get homeBatchDownloadDownloadAll =>
      'homeBatchDownload.downloadAll'.tr();
  static String get homeBatchDownloadNoValidUrls =>
      'homeBatchDownload.noValidUrls'.tr();
  static String homeBatchDownloadValidCount(int valid, int invalid) =>
      'homeBatchDownload.validCount'.tr(
        namedArgs: {'valid': '$valid', 'invalid': '$invalid'},
      );
  static String homeBatchDownloadDuplicatesRemoved(int count) =>
      'homeBatchDownload.duplicatesRemoved'.tr(namedArgs: {'count': '$count'});
  static String homeBatchDownloadDownloadCount(int count) =>
      'homeBatchDownload.downloadCount'.tr(namedArgs: {'count': '$count'});
  static String get homeBatchDownloadEmptyHint =>
      'homeBatchDownload.emptyHint'.tr();

  // ==================== SUPPORT ====================
  static String get supportNoTickets => 'support.noTickets'.tr();
  static String get supportNoTicketsSubtitle =>
      'support.noTicketsSubtitle'.tr();
  static String get supportNewTicket => 'support.newTicket'.tr();
  static String get supportSubject => 'support.subject'.tr();
  static String get supportSubjectRequired => 'support.subjectRequired'.tr();
  static String get supportCategory => 'support.category'.tr();
  static String get supportMessage => 'support.message'.tr();
  static String get supportMessageRequired => 'support.messageRequired'.tr();
  static String get supportSubmit => 'support.submit'.tr();
  static String get supportTicketChat => 'support.ticketChat'.tr();
  static String get supportNoMessages => 'support.noMessages'.tr();
  static String get supportTypeMessage => 'support.typeMessage'.tr();
  static String get supportLoadError => 'support.loadError'.tr();

  // ==================== AI ASSISTANT ====================
  static String get assistantNoSessions => 'assistant.noSessions'.tr();
  static String get assistantNoSessionsSubtitle =>
      'assistant.noSessionsSubtitle'.tr();
  static String get assistantNewChat => 'assistant.newChat'.tr();
  static String get assistantChat => 'assistant.chat'.tr();
  static String get assistantFirstMessage => 'assistant.firstMessage'.tr();
  static String get assistantFirstMessageHint =>
      'assistant.firstMessageHint'.tr(namedArgs: _brandArgs);
  static String get assistantStart => 'assistant.start'.tr();
  static String get assistantNoMessages => 'assistant.noMessages'.tr();
  static String get assistantTypeMessage => 'assistant.typeMessage'.tr();
  static String get assistantThinking => 'assistant.thinking'.tr();
  static String get assistantEscalate => 'assistant.escalate'.tr();
  static String get assistantEscalated => 'assistant.escalated'.tr();
  static String get assistantEscalateTitle => 'assistant.escalateTitle'.tr();
  static String get assistantEscalateDescription =>
      'assistant.escalateDescription'.tr();
  static String get assistantEscalateSubject =>
      'assistant.escalateSubject'.tr();
  static String get assistantEscalateSubjectHint =>
      'assistant.escalateSubjectHint'.tr();
  static String get assistantEscalateConfirm =>
      'assistant.escalateConfirm'.tr();
  static String get assistantEscalatedSuccess =>
      'assistant.escalatedSuccess'.tr();
  static String get assistantLoadError => 'assistant.loadError'.tr();
  static String get assistantAskAnything => 'assistant.askAnything'.tr();
  static String get assistantAboutDownloads =>
      'assistant.aboutDownloads'.tr(namedArgs: _brandArgs);
  static String get assistantInputHint =>
      'assistant.inputHint'.tr(namedArgs: _brandArgs);
  static String get assistantChatHistory => 'assistant.chatHistory'.tr();
  static String get assistantSearchHistory => 'assistant.searchHistory'.tr();
  static String get assistantToday => 'assistant.today'.tr();
  static String get assistantYesterday => 'assistant.yesterday'.tr();
  static String get assistantThisWeek => 'assistant.thisWeek'.tr();
  static String get assistantOlder => 'assistant.older'.tr();
  static String get assistantContextTip => 'assistant.contextTip'.tr();
  static String get assistantQuickTroubleshoot =>
      'assistant.quickTroubleshoot'.tr();
  static String get assistantQuickBestQuality =>
      'assistant.quickBestQuality'.tr();
  static String get assistantQuickBatchDownload =>
      'assistant.quickBatchDownload'.tr();
  static String get assistantQuickFailedDownload =>
      'assistant.quickFailedDownload'.tr();
  static String get assistantQuickExtractAudio =>
      'assistant.quickExtractAudio'.tr();
  static String get assistantQuickSpeedUp => 'assistant.quickSpeedUp'.tr();
  static String get assistantQuickTroubleshootMsg =>
      'assistant.quickTroubleshootMsg'.tr();
  static String get assistantQuickBestQualityMsg =>
      'assistant.quickBestQualityMsg'.tr();
  static String get assistantQuickBatchDownloadMsg =>
      'assistant.quickBatchDownloadMsg'.tr();
  static String get assistantQuickFailedDownloadMsg =>
      'assistant.quickFailedDownloadMsg'.tr();
  static String get assistantQuickExtractAudioMsg =>
      'assistant.quickExtractAudioMsg'.tr();
  static String get assistantQuickSpeedUpMsg =>
      'assistant.quickSpeedUpMsg'.tr();
  static String get assistantGreetingMorning =>
      'assistant.greetingMorning'.tr();
  static String get assistantGreetingAfternoon =>
      'assistant.greetingAfternoon'.tr();
  static String get assistantGreetingEvening =>
      'assistant.greetingEvening'.tr();
  static String get assistantGreetingQuestion =>
      'assistant.greetingQuestion'.tr();
  static String get assistantMessageCopied => 'assistant.messageCopied'.tr();
  static String get assistantCopyMessage => 'assistant.copyMessage'.tr();
  static String get assistantSessionInfo => 'assistant.sessionInfo'.tr();
  static String get assistantSuggestedActions =>
      'assistant.suggestedActions'.tr();
  static String assistantMessageCount(int count) =>
      'assistant.messageCount'.tr(namedArgs: {'count': count.toString()});
  static String get assistantFilterAll => 'assistant.filterAll'.tr();
  static String get assistantFilterActive => 'assistant.filterActive'.tr();
  static String get assistantFilterEscalated =>
      'assistant.filterEscalated'.tr();
  static String get assistantSelectSession => 'assistant.selectSession'.tr();
  static String get assistantContinueConversation =>
      'assistant.continueConversation'.tr();

  // ==================== SUPPORT CENTER ====================
  static String get supportCenterTitle => 'support.centerTitle'.tr();
  static String get supportQuickActions => 'support.quickActions'.tr();
  static String get supportYourTickets => 'support.yourTickets'.tr();
  static String get supportSeeAll => 'support.seeAll'.tr();
  static String get supportAppInfo => 'support.appInfo'.tr();
  static String get supportFeatureRequests => 'support.featureRequests'.tr();
  static String get supportBugReportDesc => 'support.bugReportDesc'.tr();
  static String get supportNewTicketDesc => 'support.newTicketDesc'.tr();
  static String get supportRateAppDesc =>
      'support.rateAppDesc'.tr(namedArgs: _brandArgs);
  static String get supportFeatureRequestDesc =>
      'support.featureRequestDesc'.tr();
  static String get supportStatusOpen => 'support.statusOpen'.tr();
  static String get supportStatusInProgress => 'support.statusInProgress'.tr();
  static String get supportStatusWaiting => 'support.statusWaiting'.tr();
  static String get supportStatusResolved => 'support.statusResolved'.tr();
  static String get supportStatusClosed => 'support.statusClosed'.tr();

  // ==================== BUG REPORT ====================
  static String get bugReportTitle => 'bugReport.title'.tr();
  static String get bugReportTitleField => 'bugReport.titleField'.tr();
  static String get bugReportTitleRequired => 'bugReport.titleRequired'.tr();
  static String get bugReportDescription => 'bugReport.description'.tr();
  static String get bugReportDescriptionRequired =>
      'bugReport.descriptionRequired'.tr();
  static String get bugReportSteps => 'bugReport.steps'.tr();
  static String get bugReportStepsHint => 'bugReport.stepsHint'.tr();
  static String get bugReportSubmit => 'bugReport.submit'.tr();
  static String get bugReportSuccess => 'bugReport.success'.tr();

  // ==================== RATING ====================
  static String get ratingTitle => 'rating.title'.tr(namedArgs: _brandArgs);
  static String get ratingSubtitle => 'rating.subtitle'.tr();
  static String get ratingReview => 'rating.review'.tr();
  static String get ratingReviewHint => 'rating.reviewHint'.tr();
  static String get ratingSubmit => 'rating.submit'.tr();
  static String get ratingSuccess => 'rating.success'.tr();

  // ==================== FEATURE REQUESTS ====================
  static String get featureRequestsTitle => 'featureRequests.title'.tr();
  static String get featureRequestsEmpty => 'featureRequests.empty'.tr();
  static String get featureRequestsSubmit => 'featureRequests.submit'.tr();
  static String get featureRequestsTitleField =>
      'featureRequests.titleField'.tr();
  static String get featureRequestsDescriptionField =>
      'featureRequests.descriptionField'.tr();

  // ==================== SETTINGS ACCOUNT ====================
  static String get settingsAccountTitle => 'settingsAccount.title'.tr();
  static String get settingsAccountDeviceRegistered =>
      'settingsAccount.deviceRegistered'.tr();
  static String get settingsAccountDeviceNotRegistered =>
      'settingsAccount.deviceNotRegistered'.tr();
  static String settingsAccountDeviceId(String id) =>
      'settingsAccount.deviceId'.tr(namedArgs: {'id': id});
  static String get settingsAccountReportBug =>
      'settingsAccount.reportBug'.tr();
  static String get settingsAccountReportBugSubtitle =>
      'settingsAccount.reportBugSubtitle'.tr();
  static String get settingsAccountRateApp =>
      'settingsAccount.rateApp'.tr(namedArgs: _brandArgs);
  static String get settingsAccountRateAppSubtitle =>
      'settingsAccount.rateAppSubtitle'.tr();
  static String get settingsAccountSupportCenter =>
      'settingsAccount.supportCenter'.tr();
  static String get settingsAccountSupportCenterSubtitle =>
      'settingsAccount.supportCenterSubtitle'.tr();

  // ==================== CSV EXPORT ====================

  static String get csvExportTooltip => 'csvExport.tooltip'.tr();
  static String get csvExportNoDownloads => 'csvExport.noDownloads'.tr();
  static String csvExportSuccess(String path) =>
      'csvExport.success'.tr(namedArgs: {'path': path});
  static String get csvExportErrorFailed => 'csvExport.errorFailed'.tr();
  static String get csvExportMenuItem => 'csvExport.menuItem'.tr();

  // ==================== NOTIFICATIONS ====================

  static String get notificationsTitle => 'notifications.title'.tr();
  static String get notificationsMarkAllRead =>
      'notifications.markAllRead'.tr();
  static String get notificationsClearAll => 'notifications.clearAll'.tr();
  static String get notificationsEmpty => 'notifications.empty'.tr();
  static String get notificationsDownloadComplete =>
      'notifications.downloadComplete'.tr();
  static String get notificationsDownloadFailed =>
      'notifications.downloadFailed'.tr();

  // ==================== NOTES ====================

  static String get notesEditNote => 'notes.editNote'.tr();
  static String get notesNoteHint => 'notes.noteHint'.tr();
  static String get notesNoteSaved => 'notes.noteSaved'.tr();
  static String get notesNoteCleared => 'notes.noteCleared'.tr();
  static String notesCharCount(int count) =>
      'notes.charCount'.tr(namedArgs: {'count': count.toString()});
  static String get notesClearNote => 'notes.clearNote'.tr();

  // ==================== YT-DLP UPDATE ====================

  static String get ytdlpUpdateCompleted => 'ytdlpUpdate.completed'.tr();
  static String ytdlpUpdateCompletedBody(String version) =>
      'ytdlpUpdate.completedBody'.tr(namedArgs: {'version': version});
  static String get ytdlpUpdateFailed => 'ytdlpUpdate.failed'.tr();
  static String get ytdlpUpdateFailedBody => 'ytdlpUpdate.failedBody'.tr();
  static String get ytdlpUpdateProgressLabel =>
      'ytdlpUpdate.progressLabel'.tr();
  static String get ytdlpUpdateNoUpdateNeeded =>
      'ytdlpUpdate.noUpdateNeeded'.tr();
  static String get ytdlpUpdateCheckingForUpdate =>
      'ytdlpUpdate.checkingForUpdate'.tr();
  static String get ytdlpUpdateRollbackSuccess =>
      'ytdlpUpdate.rollbackSuccess'.tr();

  // ==================== BINARY UPDATE ====================

  static String get binaryUpdateHintNetworkOffline =>
      'binaryUpdate.hintNetworkOffline'.tr();
  static String get binaryUpdateHintNetworkTimeout =>
      'binaryUpdate.hintNetworkTimeout'.tr();
  static String get binaryUpdateHintHttpError =>
      'binaryUpdate.hintHttpError'.tr();
  static String get binaryUpdateHintPermissionDenied =>
      'binaryUpdate.hintPermissionDenied'.tr();
  static String get binaryUpdateHintDiskFull =>
      'binaryUpdate.hintDiskFull'.tr();
  static String get binaryUpdateHintBackupFailed =>
      'binaryUpdate.hintBackupFailed'.tr();
  static String get binaryUpdateHintExtractionFailed =>
      'binaryUpdate.hintExtractionFailed'.tr();
  static String get binaryUpdateHintArchiveCorrupt =>
      'binaryUpdate.hintArchiveCorrupt'.tr();
  static String get binaryUpdateHintUnknown => 'binaryUpdate.hintUnknown'.tr();
  static String get binaryUpdateFfmpegUpdateCompleted =>
      'binaryUpdate.ffmpegUpdateCompleted'.tr();
  static String binaryUpdateFfmpegUpdateCompletedBody(String version) =>
      'binaryUpdate.ffmpegUpdateCompletedBody'.tr(
        namedArgs: {'version': version},
      );
  static String get binaryUpdateFfmpegUpdateFailed =>
      'binaryUpdate.ffmpegUpdateFailed'.tr();
  static String get binaryUpdateFfmpegUpdateFailedBody =>
      'binaryUpdate.ffmpegUpdateFailedBody'.tr();
  static String get binaryUpdateHistoryTitle =>
      'binaryUpdate.historyTitle'.tr();
  static String get binaryUpdateHistoryEmpty =>
      'binaryUpdate.historyEmpty'.tr();
  static String binaryUpdateHistorySuccess(String version) =>
      'binaryUpdate.historySuccess'.tr(namedArgs: {'version': version});
  static String get binaryUpdateHistorySuccessNoVersion =>
      'binaryUpdate.historySuccessNoVersion'.tr();
  static String binaryUpdateHistoryFailed(String error) =>
      'binaryUpdate.historyFailed'.tr(namedArgs: {'error': error});

  // ==================== ADVANCED OPTIONS ====================

  static String get advancedOptionsNetworkTuningTitle =>
      'advancedOptions.networkTuningTitle'.tr();
  static String get advancedOptionsSocketTimeout =>
      'advancedOptions.socketTimeout'.tr();
  static String get advancedOptionsSocketTimeoutDesc =>
      'advancedOptions.socketTimeoutDesc'.tr();
  static String advancedOptionsSocketTimeoutValue(int value) =>
      'advancedOptions.socketTimeoutValue'.tr(
        namedArgs: {'value': value.toString()},
      );
  static String get advancedOptionsMaxRetries =>
      'advancedOptions.maxRetries'.tr();
  static String get advancedOptionsMaxRetriesDesc =>
      'advancedOptions.maxRetriesDesc'.tr();
  static String get advancedOptionsHttpChunkSize =>
      'advancedOptions.httpChunkSize'.tr();
  static String get advancedOptionsHttpChunkSizeDesc =>
      'advancedOptions.httpChunkSizeDesc'.tr();
  static String advancedOptionsHttpChunkSizeValue(int value) =>
      'advancedOptions.httpChunkSizeValue'.tr(
        namedArgs: {'value': value.toString()},
      );
  static String get advancedOptionsFilenameTitle =>
      'advancedOptions.filenameTitle'.tr();
  static String get advancedOptionsFilenameTemplate =>
      'advancedOptions.filenameTemplate'.tr();
  static String get advancedOptionsFilenameTemplateDesc =>
      'advancedOptions.filenameTemplateDesc'.tr();
  static String advancedOptionsFilenamePreview(String preview) =>
      'advancedOptions.filenamePreview'.tr(namedArgs: {'preview': preview});
  static String get advancedOptionsFilenameInsertVariable =>
      'advancedOptions.filenameInsertVariable'.tr();
  static String get advancedOptionsPostprocessorTitle =>
      'advancedOptions.postprocessorTitle'.tr();
  static String get advancedOptionsPostprocessorArgs =>
      'advancedOptions.postprocessorArgs'.tr();
  static String get advancedOptionsPostprocessorArgsDesc =>
      'advancedOptions.postprocessorArgsDesc'.tr();
  static String get advancedOptionsPostprocessorWarning =>
      'advancedOptions.postprocessorWarning'.tr();
  static String get advancedOptionsPostprocessorHint =>
      'advancedOptions.postprocessorHint'.tr();

  // ==================== HELPER METHODS ====================

  /// Get theme mode label
  static String getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return settingsThemeLight;
      case ThemeMode.dark:
        return settingsThemeDark;
      case ThemeMode.system:
        return settingsThemeSystem;
    }
  }

  // ==================== Stream Selection ====================
  static String get streamSelectionVideoOnly =>
      'streamSelection.videoOnly'.tr();
  static String get streamSelectionNoAudio => 'streamSelection.noAudio'.tr();
  static String get streamSelectionSubtitles =>
      'streamSelection.subtitles'.tr();
  static String get streamSelectionAutoGenerated =>
      'streamSelection.autoGenerated'.tr();
  static String get streamSelectionAdvancedTitle =>
      'streamSelection.advancedTitle'.tr();
  static String get streamSelectionVideoTracks =>
      'streamSelection.videoTracks'.tr();
  static String get streamSelectionAudioTracks =>
      'streamSelection.audioTracks'.tr();
  static String get streamSelectionDownloadCombo =>
      'streamSelection.downloadCombo'.tr();
  static String get streamSelectionComboHint =>
      'streamSelection.comboHint'.tr();
  static String get streamSelectionNoRawStreams =>
      'streamSelection.noRawStreams'.tr();
  static String get streamSelectionShowAdvanced =>
      'streamSelection.showAdvanced'.tr();

  // ==================== Browser ====================

  static String get browserTitle => 'browser.title'.tr();
  static String get browserUrlPlaceholder => 'browser.urlPlaceholder'.tr();
  static String get browserBack => 'browser.back'.tr();
  static String get browserForward => 'browser.forward'.tr();
  static String get browserRefresh => 'browser.refresh'.tr();
  static String get browserHome => 'browser.home'.tr();
  static String get browserDownloadDetected => 'browser.downloadDetected'.tr();
  static String get browserDownloadVideo => 'browser.downloadVideo'.tr();
  static String get browserDownloading => 'browser.downloading'.tr();
  static String get browserErrorLoading => 'browser.errorLoading'.tr();
  static String get browserVideoDetected => 'browser.videoDetected'.tr();
  static String get browserNoVideoDetected => 'browser.noVideoDetected'.tr();
  static String get browserFacebookSniffFallback =>
      'browser.facebookSniffFallback'.tr();
  static String get browserOpenExternal => 'browser.openExternal'.tr();
  static String get browserStop => 'browser.stop'.tr();
  static String get browserFullscreenEnter => 'browser.fullscreenEnter'.tr();
  static String get browserFullscreenExit => 'browser.fullscreenExit'.tr();
  static String get browserFullscreenHint => 'browser.fullscreenHint'.tr();
  static String get browserSuggestionPlaylist =>
      'browser.suggestionPlaylist'.tr();
  static String get browserSuggestionChannel =>
      'browser.suggestionChannel'.tr();
  static String get browserSuggestionShowcase =>
      'browser.suggestionShowcase'.tr();
  static String get browserSuggestionSeries => 'browser.suggestionSeries'.tr();
  static String get browserSuggestionDownloadAll =>
      'browser.suggestionDownloadAll'.tr();
  static String get browserSuggestionDismiss =>
      'browser.suggestionDismiss'.tr();
  static String get browserAutocompleteNoResults =>
      'browser.autocompleteNoResults'.tr();
  static String get browserNewTab => 'browser.newTab'.tr();
  static String get browserCloseTab => 'browser.closeTab'.tr();
  static String get browserTabs => 'browser.tabs'.tr();
  static String get browserHistory => 'browser.history'.tr();
  static String get browserBookmarks => 'browser.bookmarks'.tr();
  static String get browserNoHistory => 'browser.noHistory'.tr();
  static String get browserNoBookmarks => 'browser.noBookmarks'.tr();
  static String get browserClearHistory => 'browser.clearHistory'.tr();
  static String get browserClearHistoryConfirm =>
      'browser.clearHistoryConfirm'.tr();
  static String get browserAddBookmark => 'browser.addBookmark'.tr();
  static String get browserRemoveBookmark => 'browser.removeBookmark'.tr();
  static String get browserBookmarkAdded => 'browser.bookmarkAdded'.tr();
  static String get browserBookmarkRemoved => 'browser.bookmarkRemoved'.tr();
  static String get browserMaxTabsReached => 'browser.maxTabsReached'.tr();
  static String get browserIncognitoNewTab => 'browser.incognitoNewTab'.tr();
  static String get browserIncognitoIndicator =>
      'browser.incognitoIndicator'.tr();
  static String get browserIncognitoNoHistory =>
      'browser.incognitoNoHistory'.tr();
  static String get browserIncognitoCookiesCleared =>
      'browser.incognitoCookiesCleared'.tr();
  static String get browserIncognitoTooltip => 'browser.incognitoTooltip'.tr();
  static String get browserBookmarkExport => 'browser.bookmarkExport'.tr();
  static String get browserBookmarkExportSuccess =>
      'browser.bookmarkExportSuccess'.tr();
  static String get browserBookmarkImport => 'browser.bookmarkImport'.tr();
  static String browserBookmarkImportSuccess(int count) =>
      'browser.bookmarkImportSuccess'.tr(args: ['$count']);
  static String get browserBookmarkImportError =>
      'browser.bookmarkImportError'.tr();
  static String get browserBookmarkImportNone =>
      'browser.bookmarkImportNone'.tr();

  // ==================== BROWSER MEDIA SNIFFING (IDM) ====================

  static String get browserMediaSniffTitle => 'browser.mediaSniffTitle'.tr();
  static String get browserYoutubeUseHomeHint =>
      'browser.youtubeUseHomeHint'.tr();
  static String get browserYoutubeOpenHome => 'browser.youtubeOpenHome'.tr();
  static String get browserDownloadStartedHome =>
      'browser.downloadStartedHome'.tr();
  static String get browserDrmTitle => 'browser.drmTitle'.tr();
  static String get browserDrmMessage => 'browser.drmMessage'.tr();
  static String get browserMediaSniffEmpty => 'browser.mediaSniffEmpty'.tr();
  static String get browserMediaSniffDownload =>
      'browser.mediaSniffDownload'.tr();
  static String get browserMediaSniffDownloadAll =>
      'browser.mediaSniffDownloadAll'.tr();
  static String get browserMediaSniffClear => 'browser.mediaSniffClear'.tr();
  static String get browserMediaSniffVideo => 'browser.mediaSniffVideo'.tr();
  static String get browserMediaSniffAudio => 'browser.mediaSniffAudio'.tr();
  static String get browserMediaSniffStream => 'browser.mediaSniffStream'.tr();
  static String get browserMediaSniffSegment =>
      'browser.mediaSniffSegment'.tr();
  static String get browserMediaSniffUnknown =>
      'browser.mediaSniffUnknown'.tr();
  static String get browserMediaSniffEnabled =>
      'browser.mediaSniffEnabled'.tr();
  static String browserMediaSniffCount(int count) =>
      'browser.mediaSniffCount'.tr(args: ['$count']);
  static String get browserMediaSniffFeedTip =>
      'browser.mediaSniffFeedTip'.tr();

  // ==================== BROWSER DOWNLOAD OVERLAY ====================

  static String browserDownloadActiveCount(int count) =>
      'browser.downloadActiveCount'.tr(args: ['$count']);
  static String get browserDownloadViewAll => 'browser.downloadViewAll'.tr();
  static String get browserDownloadQueued => 'browser.downloadQueued'.tr();
  static String get browserDownloadConverting =>
      'browser.downloadConverting'.tr();
  static String get browserDownloadPause => 'browser.downloadPause'.tr();
  static String get browserDownloadResume => 'browser.downloadResume'.tr();
  static String get browserDownloadCancel => 'browser.downloadCancel'.tr();
  static String browserDownloadStartedNotice(String title) =>
      'browser.downloadStartedNotice'.tr(args: [title]);
  static String browserDownloadCompletedNotice(String title) =>
      'browser.downloadCompletedNotice'.tr(args: [title]);

  // Cookie Management
  static String get cookieManagementTitle =>
      'browser.cookieManagementTitle'.tr();
  static String get cookieManagementImport =>
      'browser.cookieManagementImport'.tr();
  static String get cookieManagementExport =>
      'browser.cookieManagementExport'.tr();
  static String get cookieManagementClearAll =>
      'browser.cookieManagementClearAll'.tr();
  static String get cookieManagementNoSession =>
      'browser.cookieManagementNoSession'.tr();
  static String cookieManagementCookies(int count) =>
      'browser.cookieManagementCookies'.tr(args: ['$count']);
  static String get cookieManagementRelogin =>
      'browser.cookieManagementRelogin'.tr();
  static String get cookieManagementCopyCookies =>
      'browser.cookieManagementCopyCookies'.tr();
  static String cookieManagementDeletePlatform(String platform) =>
      'browser.cookieManagementDeletePlatform'.tr(args: [platform]);
  static String get cookieManagementExpired =>
      'browser.cookieManagementExpired'.tr();
  static String get cookieManagementExpiringSoon =>
      'browser.cookieManagementExpiringSoon'.tr();
  static String get cookieManagementHealthy =>
      'browser.cookieManagementHealthy'.tr();
  static String get cookieManagementShowAll =>
      'browser.cookieManagementShowAll'.tr();
  static String get cookieManagementInvalidFile =>
      'browser.cookieManagementInvalidFile'.tr();
  static String cookieManagementImportSuccess(int count) =>
      'browser.cookieManagementImportSuccess'.tr(args: ['$count']);
  static String get cookieManagementExportSuccess =>
      'browser.cookieManagementExportSuccess'.tr();
  static String cookieManagementExpiringSoonBanner(String platform) =>
      'browser.cookieManagementExpiringSoonBanner'.tr(args: [platform]);

  // ==================== AD BLOCK ====================

  static String get adBlockToggle => 'adBlock.toggle'.tr();
  static String get adBlockDescription => 'adBlock.description'.tr();
  static String get adBlockBlocked => 'adBlock.blocked'.tr();

  // ==================== POPUP BLOCKER ====================

  static String get popupBlockerToggle => 'popupBlocker.toggle'.tr();
  static String get popupBlockerDescription => 'popupBlocker.description'.tr();
  static String get popupBlockerBlocked => 'popupBlocker.blocked'.tr();

  // ==================== BROWSER SETTINGS ====================

  static String get browserSettingsContentFiltering =>
      'browserSettings.contentFiltering'.tr();
  static String browserSettingsAdsBlocked(int count) =>
      'browserSettings.adsBlocked'.tr(args: ['$count']);
  static String browserSettingsPopupsBlocked(int count) =>
      'browserSettings.popupsBlocked'.tr(args: ['$count']);
  static String get browserSettingsSecuritySection =>
      'browserSettings.securitySection'.tr();
  static String get browserSettingsSearchEngine =>
      'browserSettings.searchEngine'.tr();
  static String get browserSettingsHomePage => 'browserSettings.homePage'.tr();
  static String get browserSettingsClearData =>
      'browserSettings.clearData'.tr();
  static String get browserSettingsClearDataConfirm =>
      'browserSettings.clearDataConfirm'.tr();
  static String get browserSettingsClearDataAction =>
      'browserSettings.clearDataAction'.tr();
  static String get browserSettingsClearDataSuccess =>
      'browserSettings.clearDataSuccess'.tr();
  static String get browserSettingsResetDefault =>
      'browserSettings.resetDefault'.tr();

  // ==================== FIND IN PAGE ====================

  static String get findInPagePlaceholder => 'findInPage.placeholder'.tr();
  static String findInPageMatchCount(int current, int total) =>
      'findInPage.matchCount'.tr(args: ['$current', '$total']);
  static String get findInPageNoMatches => 'findInPage.noMatches'.tr();
  static String get findInPagePrevious => 'findInPage.previous'.tr();
  static String get findInPageNext => 'findInPage.next'.tr();
  static String get findInPageClose => 'findInPage.close'.tr();

  // ==================== BATCH VIDEO ====================

  static String get batchVideoTitle => 'batchVideo.title'.tr();
  static String get batchVideoSelectAll => 'batchVideo.selectAll'.tr();
  static String get batchVideoDeselectAll => 'batchVideo.deselectAll'.tr();
  static String batchVideoDownloadSelected(int count) =>
      'batchVideo.downloadSelected'.tr(args: ['$count']);
  static String batchVideoVideosFound(int count) =>
      'batchVideo.videosFound'.tr(args: ['$count']);
  static String get batchVideoNoVideosFound => 'batchVideo.noVideosFound'.tr();
  static String get batchVideoScanning => 'batchVideo.scanning'.tr();
  static String get batchVideoCancel => 'batchVideo.cancel'.tr();

  // ==================== NEW TAB PAGE ====================

  static String newTabSearchPlaceholder(String engineName) =>
      'newTab.searchPlaceholder'.tr(args: [engineName]);
  static String get newTabQuickAccess => 'newTab.quickAccess'.tr();
  static String get newTabRecentBookmarks => 'newTab.recentBookmarks'.tr();
  static String get newTabNoQuickAccess => 'newTab.noQuickAccess'.tr();
  static String get newTabSearchHint => 'newTab.searchHint'.tr();
  static String get newTabBookmarks => 'newTab.bookmarks'.tr();
  static String get newTabAddBookmark => 'newTab.addBookmark'.tr();
  static String get newTabAddBookmarkTitle => 'newTab.addBookmarkTitle'.tr();
  static String get newTabAddBookmarkHint => 'newTab.addBookmarkHint'.tr();
  static String get newTabRemoveBookmark => 'newTab.removeBookmark'.tr();
  static String get newTabBrowserTitle => 'newTab.browserTitle'.tr();
  static String get newTabBrowserSubtitle => 'newTab.browserSubtitle'.tr();

  // ==================== BROWSER CONTEXT MENU ====================

  static String get browserMenuDownloadVideo =>
      'browserMenu.downloadVideo'.tr();
  static String get browserMenuCopyLink => 'browserMenu.copyLink'.tr();
  static String get browserMenuOpenNewTab => 'browserMenu.openNewTab'.tr();
  static String get browserMenuOpenExternal => 'browserMenu.openExternal'.tr();
  static String get browserMenuLinkCopied => 'browserMenu.linkCopied'.tr();

  // ==================== PHISHING DETECTION ====================

  static String get phishingToggle => 'phishing.toggle'.tr();
  static String get phishingDescription => 'phishing.description'.tr();
  static String get phishingWarningTitle => 'phishing.warningTitle'.tr();
  static String get phishingWarningSuspicious =>
      'phishing.warningSuspicious'.tr();
  static String get phishingWarningDangerous =>
      'phishing.warningDangerous'.tr();
  static String get phishingProceed => 'phishing.proceed'.tr();
  static String get phishingGoBack => 'phishing.goBack'.tr();

  // ==================== HTTPS ENFORCEMENT ====================

  static String get httpsToggle => 'https.toggle'.tr();
  static String get httpsDescription => 'https.description'.tr();
  static String get httpsUpgraded => 'https.upgraded'.tr();
  static String get httpsInsecure => 'https.insecure'.tr();
  static String get httpsSecure => 'https.secure'.tr();

  // ==================== FINGERPRINT PROTECTION ====================

  static String get fingerprintToggle => 'fingerprint.toggle'.tr();
  static String get fingerprintDescription => 'fingerprint.description'.tr();

  // ==================== FFMPEG POST-PROCESSING ====================

  static String get ffmpegTimeout => 'ffmpeg.timeout'.tr();
  static String get ffmpegRetrying => 'ffmpeg.retrying'.tr();
  static String get ffmpegRetrySuccess => 'ffmpeg.retrySuccess'.tr();

  // === Multi-Segment Download ===
  static String segmentsDownloading(int count) =>
      'segments.downloading'.tr(namedArgs: {'count': count.toString()});
  static String get segmentsMerging => 'segments.merging'.tr();
  static String get segmentsFallbackSingle => 'segments.fallbackSingle'.tr();

  // === Watch Progress ===
  static String watchProgressResume(String position) =>
      'watchProgress.resume'.tr(namedArgs: {'position': position});
  static String get watchProgressResumeAction =>
      'watchProgress.resumeAction'.tr();
  static String get watchProgressStartOver => 'watchProgress.startOver'.tr();

  // === Playback Queue ===
  static String get playbackQueueTitle => 'playbackQueue.title'.tr();
  static String get playbackQueueRepeat => 'playbackQueue.repeat'.tr();
  static String get playbackQueueShuffle => 'playbackQueue.shuffle'.tr();
  static String get playbackQueueClear => 'playbackQueue.clear'.tr();
  static String get playbackQueuePlayNext => 'playbackQueue.playNext'.tr();
  static String get playbackQueueAddToQueue => 'playbackQueue.addToQueue'.tr();
  static String get playbackQueueSkipNext => 'playbackQueue.skipNext'.tr();
  static String get playbackQueueSkipPrevious =>
      'playbackQueue.skipPrevious'.tr();
  static String get playbackQueueEmpty => 'playbackQueue.empty'.tr();

  // ==================== PREMIUM ====================

  static String get premiumTitle => 'premium.title'.tr();
  static String get premiumUpgrade => 'premium.upgrade'.tr();

  /// Short pill / CTA label — fits the top-bar upgrade pill (Vietnamese
  /// "Nâng cấp", English "Upgrade"). Distinct from [premiumUpgrade]
  /// which is the longer "Nâng cấp Premium" / "Upgrade to Premium".
  static String get premiumUpgradeShort => 'premium.upgradeShort'.tr();
  static String get premiumUpgradeTitle => 'premium.upgradeTitle'.tr();
  static String get premiumUpgradeSubtitle => 'premium.upgradeSubtitle'.tr();
  static String get premiumCurrentTier => 'premium.currentTier'.tr();
  static String get premiumFree => 'premium.free'.tr();
  static String get premiumPremiumLabel => 'premium.premiumLabel'.tr();
  static String get premiumActiveSubscription =>
      'premium.activeSubscription'.tr();
  static String get premiumSubscriptionCta => 'premium.subscriptionCta'.tr();
  static String get premiumMonthly => 'premium.monthly'.tr();
  static String get premiumSemiannual => 'premium.semiannual'.tr();
  static String get premiumYearly => 'premium.yearly'.tr();
  static String get premiumYearlySave => 'premium.yearlySave'.tr();
  static String get premiumLifetime => 'premium.lifetime'.tr();
  static String get premiumLifetime1 => 'premium.lifetime1'.tr();
  static String get premiumLifetime2 => 'premium.lifetime2'.tr();
  static String get premiumLifetime3 => 'premium.lifetime3'.tr();
  static String get premiumLifetimeBadge => 'premium.lifetimeBadge'.tr();
  static String get premiumChoosePlan => 'premium.choosePlan'.tr();
  static String get premiumBillingCycle => 'premium.billingCycle'.tr();
  static String get premiumRenewsOn => 'premium.renewsOn'.tr();
  static String get premiumExpiresOn => 'premium.expiresOn'.tr();
  static String get premiumAutoRenew => 'premium.autoRenew'.tr();
  static String get premiumAutoRenewOn => 'premium.autoRenewOn'.tr();
  static String get premiumAutoRenewOff => 'premium.autoRenewOff'.tr();
  static String premiumDaysRemaining(int days) =>
      'premium.daysRemaining'.tr(namedArgs: {'days': days.toString()});
  static String get premiumCancelled => 'premium.cancelled'.tr();
  static String get premiumCancelledInfo => 'premium.cancelledInfo'.tr();
  static String get premiumCancelSubscription =>
      'premium.cancelSubscription'.tr();
  static String get premiumCancelConfirm => 'premium.cancelConfirm'.tr();
  static String get premiumCancelSuccess => 'premium.cancelSuccess'.tr();
  static String get premiumCancelFailed => 'premium.cancelFailed'.tr();
  static String get premiumExpiryWarningTitle =>
      'premium.expiryWarningTitle'.tr();
  static String premiumExpiryWarningBody(int days) =>
      'premium.expiryWarningBody'.tr(namedArgs: {'days': days.toString()});
  static String get premiumManageSubscription =>
      'premium.manageSubscription'.tr();
  static String get premiumFeatures => 'premium.features'.tr();
  static String get premiumRestorePurchase => 'premium.restorePurchase'.tr();
  static String get premiumRestoring => 'premium.restoring'.tr();
  static String get premiumRestoreSuccess => 'premium.restoreSuccess'.tr();
  static String get premiumRestoreFailed => 'premium.restoreFailed'.tr();
  static String get premiumLicenseKey => 'premium.licenseKey'.tr();
  static String get premiumPurchaseDate => 'premium.purchaseDate'.tr();
  static String get premiumTransactionId => 'premium.transactionId'.tr();
  static String get premiumDeactivate => 'premium.deactivate'.tr();
  static String get premiumDeactivateConfirm =>
      'premium.deactivateConfirm'.tr();
  static String get premiumActivateSuccess => 'premium.activateSuccess'.tr();
  static String get premiumActivateSuccessTitle =>
      'premium.activateSuccessTitle'.tr();
  static String get premiumActivateSuccessMessage =>
      'premium.activateSuccessMessage'.tr();
  static String get premiumActivateSuccessButton =>
      'premium.activateSuccessButton'.tr();
  static String get premiumActivateFailed => 'premium.activateFailed'.tr();
  static String get premiumInvalidKey => 'premium.invalidKey'.tr();
  static String get premiumHaveLicenseKey => 'premium.haveLicenseKey'.tr();
  static String get premiumHaveLicenseKeyDesc =>
      'premium.haveLicenseKeyDesc'.tr();
  static String get premiumActivateKey => 'premium.activateKey'.tr();
  static String get premiumActivateKeyDesc => 'premium.activateKeyDesc'.tr();
  static String premiumInvalidKeyFormat(String format) =>
      'premium.invalidKeyFormat'.tr(namedArgs: {'format': format});
  static String get premiumActivate => 'premium.activate'.tr();
  static String get premiumRestoreLicense => 'premium.restoreLicense'.tr();
  static String get premiumRestoreLicenseDesc =>
      'premium.restoreLicenseDesc'.tr();
  static String get premiumRestoreLicenseSuccess =>
      'premium.restoreLicenseSuccess'.tr();
  static String get premiumRestoreLicenseNotFound =>
      'premium.restoreLicenseNotFound'.tr();
  static String premiumRestoreLicenseNotFoundLegacy(String website) =>
      'premium.restoreLicenseNotFoundLegacy'.tr(
        namedArgs: {'website': website},
      );
  static String get premiumInvalidEmail => 'premium.invalidEmail'.tr();
  static String get premiumRestore => 'premium.restore'.tr();
  static String get premiumIHaveMyKey => 'premium.iHaveMyKey'.tr();
  static String get premiumSendLink => 'premium.sendLink'.tr();
  static String get premiumGateLocked => 'premium.gate.locked'.tr();
  static String get premiumGateUpgradeToUnlock =>
      'premium.gate.upgradeToUnlock'.tr();
  static String get premiumGateFeatureDescription =>
      'premium.gate.featureDescription'.tr();
  static String get premiumGateBadge =>
      'premium.gate.badge'.tr(namedArgs: _brandArgs);
  static String premiumGateWeeklyLimitReached(int limit) =>
      'premium.gate.dailyLimitReached'.tr(
        namedArgs: {'limit': limit.toString()},
      );

  @Deprecated('Use premiumGateWeeklyLimitReached')
  static String premiumGateDailyLimitReached(int limit) =>
      premiumGateWeeklyLimitReached(limit);

  // Premium feature display names
  static String get premiumFeatureUnlimitedDownloads =>
      'premium.featureNames.unlimitedDownloads'.tr();
  static String get premiumFeatureHighQuality4K =>
      'premium.featureNames.highQuality4K'.tr();
  static String get premiumFeatureExtendedConcurrent =>
      'premium.featureNames.extendedConcurrent'.tr();
  static String get premiumFeatureBatchDownload =>
      'premium.featureNames.batchDownload'.tr();
  static String get premiumFeatureAdvancedPlayer =>
      'premium.featureNames.advancedPlayer'.tr();
  static String get premiumFeatureBrowserShield =>
      'premium.featureNames.browserShield'.tr();
  static String get premiumFeatureScheduledDownloads =>
      'premium.featureNames.scheduledDownloads'.tr();
  static String get premiumFeatureBandwidthControl =>
      'premium.featureNames.bandwidthControl'.tr();
  static String get premiumFeatureSmartCollections =>
      'premium.featureNames.smartCollections'.tr();
  static String get premiumFeatureAdvancedAnalytics =>
      'premium.featureNames.advancedAnalytics'.tr();
  static String get premiumFeatureBatchImport =>
      'premium.featureNames.batchImport'.tr();
  static String get premiumFeaturePrioritySupport =>
      'premium.featureNames.prioritySupport'.tr();

  // Premium payment
  static String get premiumPaymentProcessing =>
      'premium.payment.processing'.tr();
  static String get premiumPaymentOpeningCheckout =>
      'premium.payment.openingCheckout'.tr();
  static String get premiumPaymentWaiting =>
      'premium.payment.waitingForPayment'.tr();
  static String get premiumPaymentSuccess => 'premium.payment.success'.tr();
  static String get premiumPaymentFailed => 'premium.payment.failed'.tr();
  static String get premiumPaymentCancelled => 'premium.payment.cancelled'.tr();
  static String get premiumPaymentTimeout => 'premium.payment.timeout'.tr();
  static String get premiumPaymentCannotOpenPage =>
      'premium.payment.cannotOpenPage'.tr();
  static String get premiumPaymentVerifying => 'premium.payment.verifying'.tr();
  static String get premiumReopenPaymentPage =>
      'premium.payment.reopenPage'.tr();
  static String get premiumPaymentStripeCheckout =>
      'premium.payment.stripeCheckout'.tr();
  static String get premiumPaymentCryptoCheckout =>
      'premium.payment.cryptoCheckout'.tr();
  static String get premiumPaymentPayPalCheckout =>
      'premium.payment.paypalCheckout'.tr();
  static String get premiumPaymentPayPalEmailDescription =>
      'premium.payment.paypalEmailDescription'.tr(namedArgs: _brandArgs);
  static String get premiumPaymentPayPalEmailLabel =>
      'premium.payment.paypalEmailLabel'.tr();

  // Premium crypto payment
  static String get premiumCryptoSelectCurrency =>
      'premium.payment.cryptoSelectCurrency'.tr();
  static String premiumCryptoSendTo(String amount, String currency) =>
      'premium.payment.cryptoSendTo'.tr(
        namedArgs: {'amount': amount, 'currency': currency},
      );
  static String get premiumCryptoCopyAddress =>
      'premium.payment.cryptoCopyAddress'.tr();
  static String get premiumCryptoAddressCopied =>
      'premium.payment.cryptoAddressCopied'.tr();
  static String get premiumCryptoWaitingConfirmation =>
      'premium.payment.cryptoWaitingConfirmation'.tr();
  static String premiumCryptoConfirmations(int current, int required) =>
      'premium.payment.cryptoConfirmations'.tr(
        namedArgs: {
          'current': current.toString(),
          'required': required.toString(),
        },
      );
  static String get premiumCryptoInvoiceExpired =>
      'premium.payment.cryptoInvoiceExpired'.tr();
  static String premiumCryptoInvoiceExpires(String minutes, String seconds) =>
      'premium.payment.cryptoInvoiceExpires'.tr(
        namedArgs: {'minutes': minutes, 'seconds': seconds},
      );
  static String get premiumPaymentActivationFailed =>
      'premium.payment.activationFailed'.tr();
  static String get premiumPaymentActivationFailedMessage =>
      'premium.payment.activationFailedMessage'.tr();
  static String get premiumPaymentRetryActivation =>
      'premium.payment.retryActivation'.tr();
  static String get premiumPaymentContactSupport =>
      'premium.payment.contactSupport'.tr();
  static String get premiumPaymentActivationMaxRetries =>
      'premium.payment.activationMaxRetries'.tr();
  static String premiumPaymentActivationAttempt(int current, int max) =>
      'premium.payment.activationAttempt'.tr(
        namedArgs: {'current': current.toString(), 'max': max.toString()},
      );
  static String get premiumPaymentSecureCheckout =>
      'premium.payment.secureCheckout'.tr();
  static String get premiumPaymentSecureCheckoutSubtitle =>
      'premium.payment.secureCheckoutSubtitle'.tr();
  static String get premiumPaymentSecureCheckoutTrust =>
      'premium.payment.secureCheckoutTrust'.tr(namedArgs: _brandArgs);
  static String get premiumPaymentCancelCheckout =>
      'premium.payment.cancelCheckout'.tr();
  static String get premiumPaymentStillProcessingTitle =>
      'premium.payment.stillProcessingTitle'.tr();
  static String get premiumPaymentDoNotPayAgain =>
      'premium.payment.doNotPayAgain'.tr();
  static String get premiumPaymentIAlreadyPaid =>
      'premium.payment.iAlreadyPaid'.tr();
  static String get premiumPaymentAlreadyHasPremium =>
      'premium.payment.alreadyHasPremium'.tr();

  // ==================== PREMIUM SCREEN ====================

  static String get premiumScreenCategoryAi => 'premium.screen.categoryAi'.tr();
  static String get premiumScreenCategoryCloud =>
      'premium.screen.categoryCloud'.tr();
  static String get premiumScreenCategorySecurity =>
      'premium.screen.categorySecurity'.tr();
  static String get premiumScreenCategoryAnalytics =>
      'premium.screen.categoryAnalytics'.tr();
  static String get premiumScreenCategoryDownload =>
      'premium.screen.categoryDownload'.tr();
  static String get premiumScreenCategoryOrganization =>
      'premium.screen.categoryOrganization'.tr();
  static String get premiumScreenChoosePayment =>
      'premium.screen.choosePayment'.tr();
  static String get premiumScreenStripeDesc => 'premium.screen.stripeDesc'.tr();
  static String get premiumScreenCryptoDesc => 'premium.screen.cryptoDesc'.tr();
  static String get premiumScreenPaymentMethod =>
      'premium.screen.paymentMethod'.tr();
  static String get premiumScreenPerMonth => 'premium.screen.perMonth'.tr();
  static String get premiumScreenPerSixMonths =>
      'premium.screen.perSixMonths'.tr();
  static String get premiumScreenPerYear => 'premium.screen.perYear'.tr();
  static String get premiumScreenOneTimePayment =>
      'premium.screen.oneTimePayment'.tr();
  static String get premiumScreenHeroSubtitle =>
      'premium.screen.heroSubtitle'.tr();
  static String get premiumScreenProfessionalChoice =>
      'premium.screen.professionalChoice'.tr();

  // ==================== PREMIUM VERIFICATION ====================

  static String get premiumVerificationChecking =>
      'premium.verification.checking'.tr();
  static String get premiumVerificationVerified =>
      'premium.verification.verified'.tr();
  static String premiumVerificationOfflineGrace(int days) =>
      'premium.verification.offlineGrace'.tr(
        namedArgs: {'days': days.toString()},
      );
  static String get premiumVerificationExpired =>
      'premium.verification.expired'.tr();
  static String get premiumVerificationRevoked =>
      'premium.verification.revoked'.tr();
  static String premiumVerificationDeviceLimit(int count, int max) =>
      'premium.verification.deviceLimitExceeded'.tr(
        namedArgs: {'count': count.toString(), 'max': max.toString()},
      );
  static String get premiumActivatedViaLink =>
      'premium.verification.activatedViaLink'.tr();
  static String get premiumActivatedOffline =>
      'premium.verification.activatedOffline'.tr();
  static String get premiumVerificationInvalidKey =>
      'premium.verification.invalidKey'.tr();
  static String get premiumVerificationRejected =>
      'premium.verification.rejected'.tr();

  // ==================== PREMIUM — MEMBERS LOUNGE ====================

  static String get premiumMemberTitle =>
      'premium.member.title'.tr(namedArgs: _brandArgs);
  static String get premiumMemberVipAccess => 'premium.member.vipAccess'.tr();
  static String premiumMemberSince(String date, String plan) =>
      'premium.member.since'.tr(namedArgs: {'date': date, 'plan': plan});
  static String get premiumMemberMasterKey => 'premium.member.masterKey'.tr();
  static String get premiumMemberKeyCopied => 'premium.member.keyCopied'.tr();
  static String get premiumMemberAvailableTiers =>
      'premium.member.availableTiers'.tr();
  static String get premiumMemberCurrentPlanBadge =>
      'premium.member.currentPlanBadge'.tr();
  static String get premiumMemberCreditCard => 'premium.member.creditCard'.tr();
  static String get premiumMemberCryptocurrency =>
      'premium.member.cryptocurrency'.tr();
  static String get premiumMemberNextBilling =>
      'premium.member.nextBilling'.tr();
  static String get premiumMemberAutoRenewalEnabled =>
      'premium.member.autoRenewalEnabled'.tr();
  static String get premiumMemberAutoRenewalDisabled =>
      'premium.member.autoRenewalDisabled'.tr();
  static String get premiumMemberKeepSubscription =>
      'premium.member.keepSubscription'.tr();
  static String get premiumMemberDeactivateTitle =>
      'premium.member.deactivateTitle'.tr();
  static String get premiumMemberDeactivateMessage =>
      'premium.member.deactivateMessage'.tr();
  static String get premiumMemberLicenseActive =>
      'premium.member.licenseActive'.tr();
  static String get premiumMemberAccountStatus =>
      'premium.member.accountStatus'.tr();
  static String get premiumMemberSubscriptionHealth =>
      'premium.member.subscriptionHealth'.tr();
  static String premiumMemberDaysRemaining(int days) =>
      'premium.member.daysRemaining'.tr(namedArgs: {'days': days.toString()});
  static String get premiumMemberLifetime => 'premium.member.lifetime'.tr();
  static String premiumMemberLastVerified(String date) =>
      'premium.member.lastVerified'.tr(namedArgs: {'date': date});
  static String get premiumMemberNeverVerified =>
      'premium.member.neverVerified'.tr();
  static String premiumMemberFor(String duration) =>
      'premium.member.memberFor'.tr(namedArgs: {'duration': duration});
  static String get premiumMemberJustNow => 'premium.member.justNow'.tr();
  static String get premiumMemberDaysLeft => 'premium.member.daysLeft'.tr();
  static String premiumMemberDurationYearsMonths(int years, int months) =>
      'premium.member.durationYearsMonths'.tr(
        namedArgs: {'years': years.toString(), 'months': months.toString()},
      );
  static String premiumMemberDurationYears(int years) =>
      'premium.member.durationYears'.tr(namedArgs: {'years': years.toString()});
  static String premiumMemberDurationMonths(int months) =>
      'premium.member.durationMonths'.tr(
        namedArgs: {'months': months.toString()},
      );
  static String premiumMemberDurationDays(int days) =>
      'premium.member.durationDays'.tr(namedArgs: {'days': days.toString()});
  static String get premiumMemberDurationLessThanDay =>
      'premium.member.durationLessThanDay'.tr();
  static String get premiumMemberPriceSuffixMonth =>
      'premium.member.priceSuffixMonth'.tr();
  static String get premiumMemberPriceSuffixYear =>
      'premium.member.priceSuffixYear'.tr();
  static String get premiumMemberTransactionHistory =>
      'premium.member.transactionHistory'.tr();
  static String get premiumMemberTransactionActivation =>
      'premium.member.transactionActivation'.tr();
  static String get premiumMemberTransactionRenewal =>
      'premium.member.transactionRenewal'.tr();
  static String get premiumMemberTransactionNoHistory =>
      'premium.member.transactionNoHistory'.tr();
  static String get premiumMemberTransactionDate =>
      'premium.member.transactionDate'.tr();
  static String get premiumMemberTransactionDescription =>
      'premium.member.transactionDescription'.tr();
  static String get premiumMemberTransactionAmount =>
      'premium.member.transactionAmount'.tr();
  static String get premiumMemberTransactionStatus =>
      'premium.member.transactionStatus'.tr();
  static String get premiumMemberTransactionCompleted =>
      'premium.member.transactionCompleted'.tr();
  static String get premiumMemberDeviceManagement =>
      'premium.member.deviceManagement'.tr();
  static String get premiumMemberDeviceThisDevice =>
      'premium.member.deviceThisDevice'.tr();
  static String get premiumMemberDeviceActive =>
      'premium.member.deviceActive'.tr();
  static String premiumMemberDeviceSlots(int used, int max) =>
      'premium.member.deviceSlots'.tr(
        namedArgs: {'used': used.toString(), 'max': max.toString()},
      );
  static String premiumMemberDeviceRegistered(String date) =>
      'premium.member.deviceRegistered'.tr(namedArgs: {'date': date});
  static String premiumMemberDeviceLastSeen(String date) =>
      'premium.member.deviceLastSeen'.tr(namedArgs: {'date': date});
  static String get premiumMemberDeviceRemoveTitle =>
      'premium.member.deviceRemoveTitle'.tr();
  static String get premiumMemberDeviceRemoveMessage =>
      'premium.member.deviceRemoveMessage'.tr();
  static String get premiumMemberDeviceRemoveConfirm =>
      'premium.member.deviceRemoveConfirm'.tr();
  static String get premiumMemberDeviceRemoveSuccess =>
      'premium.member.deviceRemoveSuccess'.tr();
  static String get premiumMemberDeviceRemoveError =>
      'premium.member.deviceRemoveError'.tr();
  static String get premiumMemberDeviceLoading =>
      'premium.member.deviceLoading'.tr();
  static String get premiumMemberDeviceNone => 'premium.member.deviceNone'.tr();
  static String get premiumMemberManageSubscriptionBtn =>
      'premium.member.manageSubscriptionBtn'.tr();
  static String get premiumMemberManageSubscriptionDesc =>
      'premium.member.manageSubscriptionDesc'.tr();
  static String get premiumMemberContactSupport =>
      'premium.member.contactSupport'.tr();
  static String get premiumMemberPortalNotAvailable =>
      'premium.member.portalNotAvailable'.tr();
  static String get premiumMemberPortalOpenError =>
      'premium.member.portalOpenError'.tr();

  // ==================== PREMIUM — WELCOME ====================

  static String get premiumWelcomeTitle =>
      'premium.welcome.title'.tr(namedArgs: _brandArgs);
  static String get premiumWelcomeSubtitle => 'premium.welcome.subtitle'.tr();
  static String get premiumWelcomeActivationKey =>
      'premium.welcome.activationKey'.tr();
  static String get premiumWelcomeSaveKeyWarning =>
      'premium.welcome.saveKeyWarning'.tr();
  static String get premiumWelcomeCopied => 'premium.welcome.copied'.tr();
  static String get premiumWelcomeCopy => 'premium.welcome.copy'.tr();
  static String get premiumWelcomePlanDetails =>
      'premium.welcome.planDetails'.tr();
  static String get premiumWelcomeBillingInfo =>
      'premium.welcome.billingInfo'.tr();
  static String get premiumWelcomeUnlockedFeatures =>
      'premium.welcome.unlockedFeatures'.tr();
  static String get premiumWelcomeStartExploring =>
      'premium.welcome.startExploring'.tr();
  static String get premiumWelcomePaidViaStripe =>
      'premium.welcome.paidViaStripe'.tr();
  static String get premiumWelcomePaidViaCrypto =>
      'premium.welcome.paidViaCrypto'.tr();
  static String get premiumWelcomeOneTimePurchase =>
      'premium.welcome.oneTimePurchase'.tr();
  static String get premiumWelcomeManualRenewal =>
      'premium.welcome.manualRenewal'.tr();

  // ==================== PREMIUM — CRYPTO MODAL ====================

  static String get premiumCryptoLeaveTitle => 'premium.crypto.leaveTitle'.tr();
  static String get premiumCryptoLeaveMessage =>
      'premium.crypto.leaveMessage'.tr();
  static String get premiumCryptoStay => 'premium.crypto.stay'.tr();
  static String get premiumCryptoLeave => 'premium.crypto.leave'.tr();
  static String get premiumCryptoActivation => 'premium.crypto.activation'.tr();
  static String get premiumCryptoSelectNetwork =>
      'premium.crypto.selectNetwork'.tr();
  static String premiumCryptoPayWith(String symbol) =>
      'premium.crypto.payWith'.tr(namedArgs: {'symbol': symbol});
  static String get premiumCryptoConfirmed => 'premium.crypto.confirmed'.tr();
  static String get premiumCryptoWalletAddress =>
      'premium.crypto.walletAddress'.tr();
  static String get premiumCryptoSelectPrompt =>
      'premium.crypto.selectPrompt'.tr();
  static String get premiumCryptoStatusQuote =>
      'premium.crypto.statusQuote'.tr();
  static String get premiumCryptoStatusConfirmed =>
      'premium.crypto.statusConfirmed'.tr();
  static String get premiumCryptoStatusScanning =>
      'premium.crypto.statusScanning'.tr();
  static String premiumCryptoStatusConfirmations(int current, int required) =>
      'premium.crypto.statusConfirmations'.tr(
        namedArgs: {
          'current': current.toString(),
          'required': required.toString(),
        },
      );

  // ==================== PREMIUM — GATE (additional) ====================

  static String get premiumGateTrustSignals => 'premium.gate.trustSignals'.tr();
  static String get premiumGateViewComparison =>
      'premium.gate.viewComparison'.tr();
  static String get premiumGateUnlockVault => 'premium.gate.unlockVault'.tr();

  // ==================== PREMIUM — FEATURE DESCRIPTIONS ====================

  static String get premiumFeatureDescUnlimitedDownloads =>
      'premium.featureDescs.unlimitedDownloads'.tr();
  static String get premiumFeatureDescHighQuality4K =>
      'premium.featureDescs.highQuality4K'.tr();
  static String get premiumFeatureDescExtendedConcurrent =>
      'premium.featureDescs.extendedConcurrent'.tr();
  static String get premiumFeatureDescBatchDownload =>
      'premium.featureDescs.batchDownload'.tr();
  static String get premiumFeatureDescAdvancedPlayer =>
      'premium.featureDescs.advancedPlayer'.tr();
  static String get premiumFeatureDescBrowserShield =>
      'premium.featureDescs.browserShield'.tr();
  static String get premiumFeatureDescScheduledDownloads =>
      'premium.featureDescs.scheduledDownloads'.tr();
  static String get premiumFeatureDescBandwidthControl =>
      'premium.featureDescs.bandwidthControl'.tr();
  static String get premiumFeatureDescSmartCollections =>
      'premium.featureDescs.smartCollections'.tr();
  static String get premiumFeatureDescAdvancedAnalytics =>
      'premium.featureDescs.advancedAnalytics'.tr();
  static String get premiumFeatureDescBatchImport =>
      'premium.featureDescs.batchImport'.tr();
  static String get premiumFeatureDescPrioritySupport =>
      'premium.featureDescs.prioritySupport'.tr();

  // ==================== PREMIUM — CRYPTO CONFIRMATIONS ====================

  static String get premiumCryptoConfirmBtc => 'premium.crypto.confirmBtc'.tr();
  static String get premiumCryptoConfirmLtc => 'premium.crypto.confirmLtc'.tr();
  static String get premiumCryptoConfirmXmr => 'premium.crypto.confirmXmr'.tr();

  // ==================== PREMIUM — SCREEN CATEGORY HEADERS ====================

  static String get premiumScreenCategoryAiAutomation =>
      'premium.screen.categoryAiAutomation'.tr();
  static String get premiumScreenCategoryCloudSecurity =>
      'premium.screen.categoryCloudSecurity'.tr();
  static String get premiumScreenCategoryAnalyticsPerformance =>
      'premium.screen.categoryAnalyticsPerformance'.tr();
  static String get premiumScreenCategoryDownloadPower =>
      'premium.screen.categoryDownloadPower'.tr();
  static String get premiumScreenCategoryAdvancedTools =>
      'premium.screen.categoryAdvancedTools'.tr();
  static String get premiumScreenCategoryOrganizationInsights =>
      'premium.screen.categoryOrganizationInsights'.tr();

  // ==================== PREMIUM — TRUST SIGNALS ====================

  static String get premiumTrustSecure => 'premium.trust.secure'.tr();
  static String get premiumTrustSecureDesc => 'premium.trust.secureDesc'.tr();
  static String get premiumTrustPrivate => 'premium.trust.private'.tr();
  static String get premiumTrustPrivateDesc => 'premium.trust.privateDesc'.tr();
  static String get premiumTrustSupport => 'premium.trust.support'.tr();
  static String get premiumTrustSupportDesc => 'premium.trust.supportDesc'.tr();
  static String get premiumTrustReliable => 'premium.trust.reliable'.tr();
  static String get premiumTrustReliableDesc =>
      'premium.trust.reliableDesc'.tr();

  // ==================== QUALITY FALLBACK ====================
  static String get qualityFallbackTitle => 'qualityFallback.title'.tr();
  static String get qualityFallbackDescription =>
      'qualityFallback.description'.tr();
  static String get qualityFallbackEnabled => 'qualityFallback.enabled'.tr();
  static String get qualityFallbackDisabled => 'qualityFallback.disabled'.tr();
  static String get qualityFallbackNotificationTitle =>
      'qualityFallback.notificationTitle'.tr();
  static String qualityFallbackNotificationBody(String title, String reason) =>
      'qualityFallback.notificationBody'.tr(
        namedArgs: {'title': title, 'reason': reason},
      );

  // ==================== EXTRACTION CACHE ====================
  static String get extractionCacheTitle => 'extractionCache.title'.tr();
  static String get extractionCacheDescription =>
      'extractionCache.description'.tr();
  static String get extractionCacheCacheSize =>
      'extractionCache.cacheSize'.tr();
  static String extractionCacheEntries(int count) =>
      'extractionCache.entries'.tr(namedArgs: {'count': count.toString()});
  static String get extractionCacheClearCache =>
      'extractionCache.clearCache'.tr();
  static String get extractionCacheCacheCleared =>
      'extractionCache.cacheCleared'.tr();

  // ==================== Download Archive ====================
  static String downloadArchiveDuplicateFound(String title) =>
      'downloadArchive.duplicateFound'.tr(namedArgs: {'title': title});
  static String get downloadArchiveDownloadAnyway =>
      'downloadArchive.downloadAnyway'.tr();
  static String get downloadArchiveSectionTitle =>
      'downloadArchive.sectionTitle'.tr();
  static String get downloadArchiveSectionDesc =>
      'downloadArchive.sectionDesc'.tr();
  static String downloadArchiveEntryCount(int count) =>
      'downloadArchive.entryCount'.tr(namedArgs: {'count': count.toString()});
  static String get downloadArchiveClearArchive =>
      'downloadArchive.clearArchive'.tr();
  static String get downloadArchiveClearArchiveConfirm =>
      'downloadArchive.clearArchiveConfirm'.tr();
  static String get downloadArchiveClearArchiveSuccess =>
      'downloadArchive.clearArchiveSuccess'.tr();
  static String get downloadArchiveExportArchive =>
      'downloadArchive.exportArchive'.tr();
  static String get downloadArchiveExportArchiveEmpty =>
      'downloadArchive.exportArchiveEmpty'.tr();
  static String get downloadArchiveImportArchive =>
      'downloadArchive.importArchive'.tr();
  static String downloadArchiveImportArchiveSuccess(int count) =>
      'downloadArchive.importArchiveSuccess'.tr(
        namedArgs: {'count': count.toString()},
      );

  // Orphaned files
  static String get orphanedFilesSectionTitle =>
      'orphanedFiles.sectionTitle'.tr();
  static String get orphanedFilesSectionDesc =>
      'orphanedFiles.sectionDesc'.tr();
  static String get orphanedFilesCleanButton =>
      'orphanedFiles.cleanButton'.tr();
  static String get orphanedFilesNoOrphans => 'orphanedFiles.noOrphans'.tr();
  static String orphanedFilesFound(int count, String size) =>
      'orphanedFiles.found'.tr(
        namedArgs: {'count': count.toString(), 'size': size},
      );
  static String get orphanedFilesConfirmTitle =>
      'orphanedFiles.confirmTitle'.tr();
  static String orphanedFilesConfirmBody(int count, String size) =>
      'orphanedFiles.confirmBody'.tr(
        namedArgs: {'count': count.toString(), 'size': size},
      );
  static String orphanedFilesSuccess(String size, int count) =>
      'orphanedFiles.success'.tr(
        namedArgs: {'size': size, 'count': count.toString()},
      );

  /// Change app locale
  static Future<void> changeLocale(BuildContext context, Locale locale) async {
    await context.setLocale(locale);
  }

  /// Get current locale
  static Locale getCurrentLocale(BuildContext context) {
    return context.locale;
  }

  /// Check if current locale is English
  static bool isEnglish(BuildContext context) {
    return context.locale.languageCode == 'en';
  }

  /// Check if current locale is Vietnamese
  static bool isVietnamese(BuildContext context) {
    return context.locale.languageCode == 'vi';
  }

  // Onboarding
  static String get onboardingStep1Title => 'onboarding.step1Title'.tr();
  static String get onboardingStep1Desc => 'onboarding.step1Desc'.tr();
  static String get onboardingStep2Title => 'onboarding.step2Title'.tr();
  static String get onboardingStep2Desc => 'onboarding.step2Desc'.tr();
  static String get onboardingStep3Title => 'onboarding.step3Title'.tr();
  static String get onboardingStep3Desc => 'onboarding.step3Desc'.tr();
  static String get onboardingNext => 'onboarding.next'.tr();
  static String get onboardingSkip => 'onboarding.skip'.tr();
  static String get onboardingDone => 'onboarding.done'.tr();
  static String onboardingStepOf(int step, int total) =>
      'onboarding.stepOf'.tr(namedArgs: {'step': '$step', 'total': '$total'});

  static String get keyboardPasteAndStart => 'keyboard.pasteAndStart'.tr();
  static String get keyboardPasteAndStartDesc =>
      'keyboard.pasteAndStartDesc'.tr();
  static String get keyboardPauseAll => 'keyboard.pauseAll'.tr();
  static String get keyboardPauseAllDesc => 'keyboard.pauseAllDesc'.tr();
  static String get keyboardResumeAll => 'keyboard.resumeAll'.tr();
  static String get keyboardResumeAllDesc => 'keyboard.resumeAllDesc'.tr();
  static String get keyboardOpenPlayer => 'keyboard.openPlayer'.tr();
  static String get keyboardOpenPlayerDesc => 'keyboard.openPlayerDesc'.tr();
  static String get keyboardPip => 'keyboard.pip'.tr();
  static String get keyboardPipDesc => 'keyboard.pipDesc'.tr();

  // ==================== POST-DOWNLOAD ACTIONS ====================

  static String get postDownloadActionSectionTitle =>
      'postDownloadAction.sectionTitle'.tr();
  static String get postDownloadActionSectionDesc =>
      'postDownloadAction.sectionDesc'.tr();
  static String get postDownloadActionNone =>
      'postDownloadAction.actionNone'.tr();
  static String get postDownloadActionOpenFile =>
      'postDownloadAction.actionOpenFile'.tr();
  static String get postDownloadActionOpenFolder =>
      'postDownloadAction.actionOpenFolder'.tr();
  static String get postDownloadActionMoveToFolder =>
      'postDownloadAction.actionMoveToFolder'.tr();
  static String get postDownloadActionDeleteAfterMove =>
      'postDownloadAction.actionDeleteAfterMove'.tr();
  static String get postDownloadActionTargetFolder =>
      'postDownloadAction.targetFolder'.tr();
  static String get postDownloadActionTargetFolderNotSet =>
      'postDownloadAction.targetFolderNotSet'.tr();
  static String get postDownloadActionSelectFolder =>
      'postDownloadAction.selectFolder'.tr();
  static String get postDownloadActionExecuteError =>
      'postDownloadAction.executeError'.tr();

  // ==================== TAGS ====================

  static String get tagsAddTag => 'tags.addTag'.tr();
  static String get tagsRemoveTag => 'tags.removeTag'.tr();
  static String get tagsNoTags => 'tags.noTags'.tr();
  static String get tagsTagPlaceholder => 'tags.tagPlaceholder'.tr();
  static String get tagsFilterByTag => 'tags.filterByTag'.tr();
  static String get tagsMaxLengthHint => 'tags.maxLengthHint'.tr();

  // ==================== PLAYLIST ====================

  static String playlistProgressLabel(int done, int total) =>
      'playlist.progressLabel'.tr(
        namedArgs: {'done': '$done', 'total': '$total'},
      );
  static String playlistSkippedLabel(int count) =>
      'playlist.skippedLabel'.tr(namedArgs: {'count': '$count'});
  static String playlistAllSkipped(int count) =>
      'playlist.allSkipped'.tr(namedArgs: {'count': '$count'});
  static String playlistComplete(int done, int total) =>
      'playlist.complete'.tr(namedArgs: {'done': '$done', 'total': '$total'});
  static String get playlistFetching => 'playlist.fetching'.tr();

  // Add-to-playlist dialog (user-curated collections)
  static String playlistAddDialogTitle(int count) =>
      'playlist.addDialog.title'.tr(namedArgs: {'count': '$count'});
  static String get playlistAddDialogEmpty => 'playlist.addDialog.empty'.tr();
  static String get playlistAddDialogCreateNew =>
      'playlist.addDialog.createNew'.tr();
  static String get playlistAddDialogNameHint =>
      'playlist.addDialog.nameHint'.tr();
  static String get playlistAddDialogNameRequired =>
      'playlist.addDialog.nameRequired'.tr();
  static String playlistAddDialogLoadError(String error) =>
      'playlist.addDialog.loadError'.tr(namedArgs: {'error': error});
  static String get playlistAddDialogCreateButton =>
      'playlist.addDialog.createButton'.tr();
  static String playlistAddSuccess(int count, String name) =>
      'playlist.addSuccess'.tr(namedArgs: {'count': '$count', 'name': name});
  static String get playlistRowMenuAddTo => 'playlist.rowMenu.addTo'.tr();
  static String get playlistRowMenuMoveUp => 'playlist.rowMenu.moveUp'.tr();
  static String get playlistRowMenuMoveDown => 'playlist.rowMenu.moveDown'.tr();
  static String get playlistManageCreateTitle =>
      'playlist.manage.createTitle'.tr();
  static String get playlistManageCreateCardSubtitle =>
      'playlist.manage.createCardSubtitle'.tr();
  static String get playlistManageRenameTitle =>
      'playlist.manage.renameTitle'.tr();
  static String get playlistManageDeleteTitle =>
      'playlist.manage.deleteTitle'.tr();
  static String playlistManageDeleteMessage(String name) =>
      'playlist.manage.deleteMessage'.tr(namedArgs: {'name': name});
  static String playlistManageCreated(String name) =>
      'playlist.manage.created'.tr(namedArgs: {'name': name});
  static String get playlistManageRenamed => 'playlist.manage.renamed'.tr();
  static String get playlistManageDeleted => 'playlist.manage.deleted'.tr();
  static String get playlistManageRemoved => 'playlist.manage.removed'.tr();
  static String get playlistManageOrderUpdated =>
      'playlist.manage.orderUpdated'.tr();

  // ==================== WATCH STATUS ====================

  static String get watchStatusWatched => 'watchStatus.watched'.tr();
  static String get watchStatusUnwatched => 'watchStatus.unwatched'.tr();
  static String get watchStatusMarkWatched => 'watchStatus.markWatched'.tr();
  static String get watchStatusMarkUnwatched =>
      'watchStatus.markUnwatched'.tr();
  static String get watchStatusFilterAll => 'watchStatus.filterAll'.tr();
  static String get watchStatusFilterWatched =>
      'watchStatus.filterWatched'.tr();
  static String get watchStatusFilterWatching =>
      'watchStatus.filterWatching'.tr();
  static String get watchStatusFilterUnwatched =>
      'watchStatus.filterUnwatched'.tr();

  // ==================== COLLECTIONS ====================

  static String get collectionsTitle => 'collections.title'.tr();
  static String get collectionsAddCollection =>
      'collections.addCollection'.tr();
  static String get collectionsEditCollection =>
      'collections.editCollection'.tr();
  static String get collectionsSave => 'collections.save'.tr();
  static String get collectionsAdd => 'collections.add'.tr();
  static String get collectionsCancel => 'collections.cancel'.tr();
  static String get collectionsDelete => 'collections.delete'.tr();
  static String get collectionsDeleteTitle => 'collections.deleteTitle'.tr();
  static String collectionsDeleteConfirm(String name) =>
      'collections.deleteConfirm'.tr(namedArgs: {'name': name});
  static String get collectionsCollectionName =>
      'collections.collectionName'.tr();
  static String get collectionsNameRequired => 'collections.nameRequired'.tr();
  static String get collectionsDescription => 'collections.description'.tr();
  static String get collectionsFilterPlatform =>
      'collections.filterPlatform'.tr();
  static String get collectionsFilterStatus => 'collections.filterStatus'.tr();
  static String get collectionsEmptyTitle => 'collections.emptyTitle'.tr();
  static String get collectionsEmptySubtitle =>
      'collections.emptySubtitle'.tr();
  static String get collectionsNoItems => 'collections.noItems'.tr();
  static String collectionsItemCount(int count) =>
      'collections.itemCount'.tr(namedArgs: {'count': '$count'});

  // ==================== SORTING RULES ====================

  static String get sortingRulesTitle => 'sortingRules.title'.tr();
  static String get sortingRulesAddRule => 'sortingRules.addRule'.tr();
  static String get sortingRulesEditRule => 'sortingRules.editRule'.tr();
  static String get sortingRulesSave => 'sortingRules.save'.tr();
  static String get sortingRulesAdd => 'sortingRules.add'.tr();
  static String get sortingRulesCancel => 'sortingRules.cancel'.tr();
  static String get sortingRulesDelete => 'sortingRules.delete'.tr();
  static String get sortingRulesDeleteTitle => 'sortingRules.deleteTitle'.tr();
  static String sortingRulesDeleteConfirm(String name) =>
      'sortingRules.deleteConfirm'.tr(namedArgs: {'name': name});
  static String get sortingRulesRuleName => 'sortingRules.ruleName'.tr();
  static String get sortingRulesNameRequired =>
      'sortingRules.nameRequired'.tr();
  static String get sortingRulesConditions => 'sortingRules.conditions'.tr();
  static String get sortingRulesPlatform => 'sortingRules.platform'.tr();
  static String get sortingRulesFileExt => 'sortingRules.fileExt'.tr();
  static String get sortingRulesUrlContains => 'sortingRules.urlContains'.tr();
  static String get sortingRulesDestFolder => 'sortingRules.destFolder'.tr();
  static String get sortingRulesRenameTemplate =>
      'sortingRules.renameTemplate'.tr();
  static String get sortingRulesHint => 'sortingRules.hint'.tr();
  static String get sortingRulesEmptyTitle => 'sortingRules.emptyTitle'.tr();
  static String get sortingRulesEmptySubtitle =>
      'sortingRules.emptySubtitle'.tr();

  // ==================== SCHEDULE ====================

  static String get scheduleTitle => 'schedule.title'.tr();
  static String get schedulePickDateTime => 'schedule.pickDateTime'.tr();
  static String scheduleScheduledFor(String datetime) =>
      'schedule.scheduledFor'.tr(namedArgs: {'datetime': datetime});
  static String get scheduleClearSchedule => 'schedule.clearSchedule'.tr();
  static String scheduleSet(String time) =>
      'schedule.scheduleSet'.tr(namedArgs: {'time': time});
  static String get scheduleCleared => 'schedule.scheduleCleared'.tr();
  static String get scheduleAction => 'schedule.action'.tr();
  static String get scheduleRecurrenceNone => 'schedule.recurrenceNone'.tr();
  static String get scheduleRecurrenceDaily => 'schedule.recurrenceDaily'.tr();
  static String get scheduleRecurrenceWeekdays =>
      'schedule.recurrenceWeekdays'.tr();
  static String get scheduleRecurrenceWeekends =>
      'schedule.recurrenceWeekends'.tr();
  static String get scheduleRecurrenceCustom =>
      'schedule.recurrenceCustom'.tr();

  // ==================== TRAY MENU ====================

  static String get trayShowApp => 'tray.showApp'.tr(namedArgs: _brandArgs);
  static String get trayNewDownload => 'tray.newDownload'.tr();
  static String get trayShowDownloads => 'tray.showDownloads'.tr();
  static String get traySettings => 'tray.settings'.tr();
  static String get trayQuit => 'tray.quit'.tr(namedArgs: _brandArgs);

  // ==================== BANDWIDTH ====================

  static String get bandwidthTitle => 'bandwidth.title'.tr();
  static String get bandwidthUnlimited => 'bandwidth.unlimited'.tr();
  static String bandwidthLimitKbps(int kbps) =>
      'bandwidth.limitKbps'.tr(namedArgs: {'kbps': '$kbps'});
  static String bandwidthCurrentLimit(String value) =>
      'bandwidth.currentLimit'.tr(namedArgs: {'value': value});

  // ==================== WIFI-ONLY MODE ====================

  static String get wifiOnlyTitle => 'wifiOnly.title'.tr();
  static String get wifiOnlyDesc => 'wifiOnly.desc'.tr();
  static String get wifiOnlyNotOnWifi => 'wifiOnly.notOnWifi'.tr();

  // ==================== AUTO-THROTTLE ====================

  static String get autoThrottleTitle => 'autoThrottle.title'.tr();
  static String get autoThrottleDesc => 'autoThrottle.desc'.tr();
  static String get autoThrottleTooltip => 'autoThrottle.tooltip'.tr();

  // ==================== BATCH OPS ====================

  static String batchOpsSelected(int count) =>
      'batchOps.selected'.tr(namedArgs: {'count': '$count'});
  static String get batchOpsSelectAll => 'batchOps.selectAll'.tr();
  static String get batchOpsDeselectAll => 'batchOps.deselectAll'.tr();
  static String get batchOpsDelete => 'batchOps.delete'.tr();
  static String get batchOpsMove => 'batchOps.move'.tr();
  static String get batchOpsRename => 'batchOps.rename'.tr();
  static String batchOpsDeleteConfirmTitle(int count) =>
      'batchOps.deleteConfirmTitle'.tr(namedArgs: {'count': '$count'});
  static String get batchOpsDeleteConfirmBody =>
      'batchOps.deleteConfirmBody'.tr();
  static String get batchOpsDeleteConfirmKeepFiles =>
      'batchOps.deleteConfirmKeepFiles'.tr();
  static String get batchOpsMoveDialogTitle => 'batchOps.moveDialogTitle'.tr();
  static String get batchOpsRenameDialogTitle =>
      'batchOps.renameDialogTitle'.tr();
  static String get batchOpsRenamePatternHint =>
      'batchOps.renamePatternHint'.tr();
  static String get batchOpsRenamePatternHelp =>
      'batchOps.renamePatternHelp'.tr();
  static String get batchOpsRenamePreviewLabel =>
      'batchOps.renamePreviewLabel'.tr();
  static String batchOpsSuccessDelete(int count) =>
      'batchOps.successDelete'.tr(namedArgs: {'count': '$count'});
  static String batchOpsSuccessMove(int count) =>
      'batchOps.successMove'.tr(namedArgs: {'count': '$count'});
  static String batchOpsSuccessRename(int count) =>
      'batchOps.successRename'.tr(namedArgs: {'count': '$count'});
  static String batchOpsPartialFailure(int succeeded, int failed) =>
      'batchOps.partialFailure'.tr(
        namedArgs: {'succeeded': '$succeeded', 'failed': '$failed'},
      );
  static String get batchOpsRetry => 'batchOps.retry'.tr();
  static String batchOpsSuccessRetry(int count) =>
      'batchOps.successRetry'.tr(namedArgs: {'count': '$count'});

  // === Duplicate Download Detection ===
  static String get duplicateDownloadCompletedTitle =>
      'duplicateDownload.completedTitle'.tr();
  static String duplicateDownloadCompletedBody(String filename) =>
      'duplicateDownload.completedBody'.tr(namedArgs: {'filename': filename});
  static String get duplicateDownloadInProgressTitle =>
      'duplicateDownload.inProgressTitle'.tr();
  static String get duplicateDownloadInProgressBody =>
      'duplicateDownload.inProgressBody'.tr();
  static String get duplicateDownloadDownloadAgain =>
      'duplicateDownload.downloadAgain'.tr();
  static String get duplicateDownloadViewDownload =>
      'duplicateDownload.viewDownload'.tr();
  static String get duplicateDownloadCancel => 'duplicateDownload.cancel'.tr();

  // === Clipboard URL Detection ===
  static String get clipboardUrlDetected => 'clipboard.urlDetected'.tr();
  static String get clipboardDownload => 'clipboard.download'.tr();
  static String get clipboardDismiss => 'clipboard.dismiss'.tr();

  // === In-App Update ===
  static String get updateAvailable => 'update.available'.tr();
  static String get updateCurrent => 'update.current'.tr();
  static String get updateLatest => 'update.latest'.tr();
  static String get updateMandatory =>
      'update.mandatory'.tr(namedArgs: _brandArgs);
  static String get updateWhatsNew => 'update.whatsNew'.tr();
  static String get updateLater => 'update.later'.tr();
  static String get updateDownloadUpdate => 'update.downloadUpdate'.tr();
  static String get updateNow => 'update.updateNow'.tr();
  static String get updateRestartToUpdate => 'update.restartToUpdate'.tr();
  static String get updateRestartNow => 'update.restartNow'.tr();
  static String get updateRetry => 'update.retry'.tr();
  static String updateDownloadingProgress({
    required String percent,
    required String received,
    required String total,
  }) => 'update.downloadingProgress'.tr(
    namedArgs: {'percent': percent, 'received': received, 'total': total},
  );
  static String get updatePreparingInstall => 'update.preparingInstall'.tr();

  // === Drag & Drop ===
  static String get dragDropHint => 'dragDrop.hint'.tr();

  // === Usage Statistics ===
  static String get usageStatsTitle => 'usageStats.title'.tr();
  static String get usageStatsTotalDownloads =>
      'usageStats.totalDownloads'.tr();
  static String get usageStatsCompleted => 'usageStats.completed'.tr();
  static String get usageStatsFailed => 'usageStats.failed'.tr();
  static String get usageStatsTotalData => 'usageStats.totalData'.tr();
  static String get usageStatsByPlatform => 'usageStats.byPlatform'.tr();

  // === Settings Export/Import ===
  static String get settingsExport => 'settingsBackup.export'.tr();
  static String get settingsImport => 'settingsBackup.import'.tr();
  static String get settingsExportSuccess =>
      'settingsBackup.exportSuccess'.tr();
  static String get settingsImportSuccess =>
      'settingsBackup.importSuccess'.tr();
  static String get settingsImportError => 'settingsBackup.importError'.tr();
  static String get settingsBackupRestore => 'settingsBackup.title'.tr();

  // === Offline ===
  static String get offlineBanner => 'offline.banner'.tr();
  static String offlineQueuedCount(int count) =>
      'offline.queuedCount'.tr(args: ['$count']);

  // === Format Presets ===
  static String get formatPresetsTitle => 'formatPresets.title'.tr();
  static String get formatPresetsSaveCurrent =>
      'formatPresets.saveCurrent'.tr();
  static String get formatPresetsNameHint => 'formatPresets.nameHint'.tr();
  static String get formatPresetsSaveButton => 'formatPresets.saveButton'.tr();
  static String get formatPresetsApplied => 'formatPresets.applied'.tr();
  static String get formatPresetsSaved => 'formatPresets.saved'.tr();
  static String get formatPresetsDeleted => 'formatPresets.deleted'.tr();
  static String get formatPresetsDeleteConfirm =>
      'formatPresets.deleteConfirm'.tr();

  // === Binary Health ===
  static String binaryMissing(String names) =>
      'binary.missing'.tr(args: [names]);

  // === Auto-Update ===
  static String get autoUpdateDownloading => 'autoUpdate.downloading'.tr();
  static String get autoUpdateVerifying => 'autoUpdate.verifying'.tr();
  static String get autoUpdateReadyToInstall =>
      'autoUpdate.readyToInstall'.tr();
  static String get autoUpdateInstalling => 'autoUpdate.installing'.tr();
  static String get autoUpdateFailed => 'autoUpdate.failed'.tr();
  static String get autoUpdateInstallNow => 'autoUpdate.installNow'.tr();
  static String get autoUpdateDismiss => 'autoUpdate.dismiss'.tr();
  static String get autoUpdateRestartRequired =>
      'autoUpdate.restartRequired'.tr();
  static String get autoUpdateDownloadComplete =>
      'autoUpdate.downloadComplete'.tr();

  // ==================== ACTIVITY CENTER ====================

  static String get activityCenterTitle => 'activityCenter.title'.tr();
  static String get activityCenterBack => 'activityCenter.back'.tr();
  static String get activityCenterSearchHint =>
      'activityCenter.searchHint'.tr();
  static String get activityCenterMarkAllRead =>
      'activityCenter.markAllRead'.tr();
  static String get activityCenterTabAll => 'activityCenter.tabAll'.tr();
  static String get activityCenterTabActive => 'activityCenter.tabActive'.tr();
  static String get activityCenterTabSuccess =>
      'activityCenter.tabSuccess'.tr();
  static String get activityCenterTabErrors => 'activityCenter.tabErrors'.tr();
  static String get activityCenterTabSystem => 'activityCenter.tabSystem'.tr();
  static String get activityCenterDateToday => 'activityCenter.dateToday'.tr();
  static String get activityCenterDateLast7Days =>
      'activityCenter.dateLast7Days'.tr();
  static String get activityCenterDateLast30Days =>
      'activityCenter.dateLast30Days'.tr();
  static String get activityCenterDateAllTime =>
      'activityCenter.dateAllTime'.tr();
  static String get activityCenterDateRange => 'activityCenter.dateRange'.tr();
  static String get activityCenterTotalDownloads =>
      'activityCenter.totalDownloads'.tr();
  static String get activityCenterSuccessRate =>
      'activityCenter.successRate'.tr();
  static String get activityCenterDataProcessed =>
      'activityCenter.dataProcessed'.tr();
  static String get activityCenterActiveNow => 'activityCenter.activeNow'.tr();
  static String get activityCenterNoActivity =>
      'activityCenter.noActivity'.tr();
  static String get activityCenterNoActivityHint =>
      'activityCenter.noActivityHint'.tr();
  static String get activityCenterToday => 'activityCenter.today'.tr();
  static String get activityCenterYesterday => 'activityCenter.yesterday'.tr();
  static String get activityCenterOpenFile => 'activityCenter.openFile'.tr();
  static String get activityCenterShowInFolder =>
      'activityCenter.showInFolder'.tr();
  static String get activityCenterCopyUrl => 'activityCenter.copyUrl'.tr();
  static String get activityCenterRetry => 'activityCenter.retry'.tr();
  static String get activityCenterUrlCopied => 'activityCenter.urlCopied'.tr();
  static String get activityCenterSectionDownloadActivity =>
      'activityCenter.sectionDownloadActivity'.tr();
  static String get activityCenterSectionSuccessRate =>
      'activityCenter.sectionSuccessRate'.tr();
  static String get activityCenterSectionFormatDistribution =>
      'activityCenter.sectionFormatDistribution'.tr();
  static String get activityCenterSectionTopPlatforms =>
      'activityCenter.sectionTopPlatforms'.tr();
  static String get activityCenterActivity28Days =>
      'activityCenter.activity28Days'.tr();
  static String activityCenterTotalCount(int count) =>
      'activityCenter.totalCount'.tr(namedArgs: {'count': count.toString()});
  static String get activityCenterHeatmapLess =>
      'activityCenter.heatmapLess'.tr();
  static String get activityCenterHeatmapMore =>
      'activityCenter.heatmapMore'.tr();
  static String get activityCenterHeatmapNoActivity =>
      'activityCenter.heatmapNoActivity'.tr();
  static String activityCenterHeatmapDownload(int count) =>
      count == 1
          ? 'activityCenter.heatmapDownload'.tr(
            namedArgs: {'count': count.toString()},
          )
          : 'activityCenter.heatmapDownloads'.tr(
            namedArgs: {'count': count.toString()},
          );
  static String get activityCenterDonutSuccess =>
      'activityCenter.donutSuccess'.tr();
  static String activityCenterLegendSuccess(int count) =>
      'activityCenter.legendSuccess'.tr(namedArgs: {'count': count.toString()});
  static String activityCenterLegendFailed(int count) =>
      'activityCenter.legendFailed'.tr(namedArgs: {'count': count.toString()});
  static String get activityCenterNoCompletedDownloads =>
      'activityCenter.noCompletedDownloads'.tr();
  static String get activityCenterNoDownloads =>
      'activityCenter.noDownloads'.tr();
  static String get activityCenterOther => 'activityCenter.other'.tr();
  static String get activityCenterDayMon => 'activityCenter.dayMon'.tr();
  static String get activityCenterDayTue => 'activityCenter.dayTue'.tr();
  static String get activityCenterDayWed => 'activityCenter.dayWed'.tr();
  static String get activityCenterDayThu => 'activityCenter.dayThu'.tr();
  static String get activityCenterDayFri => 'activityCenter.dayFri'.tr();
  static String get activityCenterDaySat => 'activityCenter.daySat'.tr();
  static String get activityCenterDaySun => 'activityCenter.daySun'.tr();
  static String get activityCenterStatusPending =>
      'activityCenter.statusPending'.tr();
  static String get activityCenterStatusQueued =>
      'activityCenter.statusQueued'.tr();
  static String get activityCenterStatusDownloading =>
      'activityCenter.statusDownloading'.tr();
  static String get activityCenterStatusConverting =>
      'activityCenter.statusConverting'.tr();
  static String get activityCenterStatusPaused =>
      'activityCenter.statusPaused'.tr();
  static String get activityCenterStatusCompleted =>
      'activityCenter.statusCompleted'.tr();
  static String get activityCenterStatusFailed =>
      'activityCenter.statusFailed'.tr();
  static String get activityCenterStatusCancelled =>
      'activityCenter.statusCancelled'.tr();
  static String get activityCenterStatusWaitingForNetwork =>
      'activityCenter.statusWaitingForNetwork'.tr();

  // === Floating Capture (v2.1) ===
  // Used by main-engine UI only (Settings card). Popup engine has its
  // own i18n table — see lib/floating_window_main.dart.
  static String get floatingCaptureSettingsTitle =>
      'floatingCapture.settingsTitle'.tr();
  static String get floatingCaptureSettingsSubtitle =>
      'floatingCapture.settingsSubtitle'.tr();
  static String get floatingCaptureStatusLabel =>
      'floatingCapture.statusLabel'.tr();
  static String get floatingCaptureStatusActive =>
      'floatingCapture.statusActive'.tr();
  static String get floatingCaptureStatusManualSnooze =>
      'floatingCapture.statusManualSnooze'.tr();
  static String floatingCaptureStatusTimedSnooze(String time) =>
      'floatingCapture.statusTimedSnooze'.tr(namedArgs: {'time': time});
  static String get floatingCaptureActionResume =>
      'floatingCapture.actionResume'.tr();

  // v2.2 anti-spam reset (Phase 2A)
  static String get floatingCaptureResetCooldownsLabel =>
      'floatingCapture.resetCooldownsLabel'.tr();
  static String get floatingCaptureResetCooldownsSubtitle =>
      'floatingCapture.resetCooldownsSubtitle'.tr();
  static String get floatingCaptureResetCooldownsAction =>
      'floatingCapture.resetCooldownsAction'.tr();
  static String get floatingCaptureResetCooldownsDone =>
      'floatingCapture.resetCooldownsDone'.tr();

  // ==================== RIGHT PANEL TABS ====================
  // B.2 — sidebar tabs rendered below the embedded player. Empty
  // strings are fallbacks for nothing-to-render states.

  static String get rightPanelTabsPlaylist => 'rightPanel.tabs.playlist'.tr();
  static String get rightPanelTabsSubsAudio => 'rightPanel.tabs.subsAudio'.tr();
  static String get rightPanelTabsChapters => 'rightPanel.tabs.chapters'.tr();

  static String get rightPanelPlaylistEmpty =>
      'rightPanel.playlistTab.empty'.tr();
  static String get rightPanelPlaylistShuffle =>
      'rightPanel.playlistTab.shuffle'.tr();
  static String get rightPanelPlaylistRepeat =>
      'rightPanel.playlistTab.repeat'.tr();

  /// Pluralized item count — `{count} item` / `{count} items`.
  /// Uses easy_localization `.plural()` API matching VOICE.md §10 plural mechanic.
  /// VI is count-neutral (one == other); EN proper singular/plural;
  /// 13 other locales use machine-quality forms with TODO native review v2.1.
  static String rightPanelPlaylistItemCount(int count) =>
      'rightPanel.playlistTab.itemCount'.plural(
        count,
        namedArgs: {'count': count.toString()},
      );

  static String get rightPanelSubsAudioNotReady =>
      'rightPanel.subsAudioTab.notReady'.tr();
  static String get rightPanelSubsAudioEmpty =>
      'rightPanel.subsAudioTab.empty'.tr();
  static String rightPanelSubsAudioAudioHeader(int count) =>
      'rightPanel.subsAudioTab.audioHeader'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String rightPanelSubsAudioSubtitlesHeader(int count) =>
      'rightPanel.subsAudioTab.subtitlesHeader'.tr(
        namedArgs: {'count': count.toString()},
      );
  static String get rightPanelSubsAudioOff =>
      'rightPanel.subsAudioTab.off'.tr();
  static String rightPanelSubsAudioTrackFallback(int index) =>
      'rightPanel.subsAudioTab.trackFallback'.tr(
        namedArgs: {'index': index.toString()},
      );

  static String get rightPanelChaptersEmpty =>
      'rightPanel.chaptersTab.empty'.tr();

  // ==================== SETTINGS — PLAYER ====================
  // B.3 — Player perf opt-in toggle.

  static String get settingsPlayerCardTitle => 'settingsPlayer.cardTitle'.tr();
  static String get settingsPlayerHardwareDecodeTitle =>
      'settingsPlayer.hardwareDecodeTitle'.tr();
  static String get settingsPlayerHardwareDecodeSubtitle =>
      'settingsPlayer.hardwareDecodeSubtitle'.tr();

  // ==================== CONVERTER — additional snackbar/error keys ====================

  static String get converterConvertedFileNotFound =>
      'converter.convertedFileNotFound'.tr();
  static String get converterFileNotPlayable =>
      'converter.fileNotPlayable'.tr();
  static String get converterOpenPickerFailed =>
      'converter.openPickerFailed'.tr();

  // ==================== ASSISTANT DIAGNOSTICS PANEL ====================

  static String get assistantDiagnosticsReportBug =>
      'assistantDiagnostics.reportBug'.tr();
  static String get assistantDiagnosticsGetHelp =>
      'assistantDiagnostics.getHelp'.tr();
  static String get assistantDiagnosticsStat24hErrors =>
      'assistantDiagnostics.stat24hErrors'.tr();
  static String get assistantDiagnosticsStatHealRate =>
      'assistantDiagnostics.statHealRate'.tr();
  static String get assistantDiagnosticsStatPatterns =>
      'assistantDiagnostics.statPatterns'.tr();

  // ==================== BROWSER — history dividers + tab defaults ====================
  static String get browserHistoryToday => 'browser.historyToday'.tr();
  static String get browserHistoryYesterday => 'browser.historyYesterday'.tr();
  static String get browserHistoryThisWeek => 'browser.historyThisWeek'.tr();
  static String get browserHistoryOlder => 'browser.historyOlder'.tr();
  static String get browserNewTabTitle => 'browser.newTabTitle'.tr();
  static String get browserIncognitoTabTitle =>
      'browser.incognitoTabTitle'.tr();

  // ==================== SETTINGS — card titles (replace ALL CAPS hardcoded) ====================
  static String get settingsMediaCardThumbnails =>
      'settingsMedia.cardThumbnails'.tr();
  static String get settingsMediaCardMetadata =>
      'settingsMedia.cardMetadata'.tr();
  static String get settingsMediaCardSponsorBlock =>
      'settingsMedia.cardSponsorBlock'.tr();
  static String get settingsNetworkCardAutoThrottle =>
      'settingsNetwork.cardAutoThrottle'.tr();
  static String get settingsNetworkCardQuietHours =>
      'settingsNetwork.cardQuietHours'.tr();
  static String get settingsNetworkCardProxy =>
      'settingsNetwork.cardProxy'.tr();
  static String get settingsNetworkCardGeoBypass =>
      'settingsNetwork.cardGeoBypass'.tr();
  static String get settingsNetworkCardFilters =>
      'settingsNetwork.cardFilters'.tr();

  // ==================== BUG REPORT + CREATE TICKET ====================
  static String get bugReportSubtitleErrorContext =>
      'bugReport.subtitleErrorContext'.tr();
  static String get bugReportSubtitleGeneric =>
      'bugReport.subtitleGeneric'.tr();
  static String get bugReportContextBanner => 'bugReport.contextBanner'.tr();
  static String get createTicketCategoryGeneral =>
      'createTicket.categoryGeneral'.tr();
  static String get createTicketCategoryBilling =>
      'createTicket.categoryBilling'.tr();
  static String get createTicketCategoryTechnical =>
      'createTicket.categoryTechnical'.tr();
  static String get createTicketCategoryFeatureRequest =>
      'createTicket.categoryFeatureRequest'.tr();
  static String get createTicketSubtitleDirectLine =>
      'createTicket.subtitleDirectLine'.tr();
  static String get bugReportAttachDiagnosticLogs =>
      'bugReport.attachDiagnosticLogs'.tr();

  // ==================== FORMATTERS — relative time (locale-aware) ====================
  static String get formattersRelativeTimeJustNow =>
      'formatters.relativeTimeJustNow'.tr();
  static String formattersRelativeTimeMinutesAgo(int count) =>
      'formatters.relativeTimeMinutesAgo'.tr(namedArgs: {'count': '$count'});
  static String formattersRelativeTimeHoursAgo(int count) =>
      'formatters.relativeTimeHoursAgo'.tr(namedArgs: {'count': '$count'});
  static String formattersRelativeTimeDaysAgo(int count) =>
      'formatters.relativeTimeDaysAgo'.tr(namedArgs: {'count': '$count'});
  static String formattersRelativeTimeInMinutes(int count) =>
      'formatters.relativeTimeInMinutes'.tr(namedArgs: {'count': '$count'});
  static String formattersRelativeTimeInHours(int count) =>
      'formatters.relativeTimeInHours'.tr(namedArgs: {'count': '$count'});
  static String formattersRelativeTimeInDays(int count) =>
      'formatters.relativeTimeInDays'.tr(namedArgs: {'count': '$count'});
}
