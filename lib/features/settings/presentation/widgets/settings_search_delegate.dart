import 'package:flutter/material.dart';
import '../../../../core/l10n/app_localizations.dart';

/// A search result pointing to a specific setting item within a section.
class SettingsSearchResult {
  final int sectionIndex;
  final String sectionLabel;
  final IconData sectionIcon;
  final String settingLabel;

  const SettingsSearchResult({
    required this.sectionIndex,
    required this.sectionLabel,
    required this.sectionIcon,
    required this.settingLabel,
  });
}

/// Indexes all settings labels and returns matching results for a query.
///
/// Each searchable entry maps a setting label to its section index.
/// When the user types a query, case-insensitive substring matching
/// runs on both the label and the section name.
class SettingsSearchDelegate {
  List<SettingsSearchResult>? _cachedIndex;

  /// For testing: inject a custom index instead of building from l10n.
  SettingsSearchDelegate();

  /// Creates a delegate with a pre-built index (for testing).
  static SettingsSearchDelegate forTest(List<SettingsSearchResult> entries) {
    final delegate = SettingsSearchDelegate();
    delegate._cachedIndex = entries;
    return delegate;
  }

  /// Build the searchable index from localized strings.
  List<SettingsSearchResult> _buildIndex() {
    return [
      // Section 0: General
      _e(0, Icons.tune, _general, AppLocalizations.settingsTheme),
      _e(0, Icons.tune, _general, AppLocalizations.settingsLanguage),
      _e(0, Icons.tune, _general, AppLocalizations.settingsEnableNotifications),

      // Section 1: Downloads
      _e(
        1,
        Icons.download,
        _downloads,
        AppLocalizations.settingsDownloadLocation,
      ),
      _e(
        1,
        Icons.download,
        _downloads,
        AppLocalizations.settingsConcurrentDownloads,
      ),
      _e(
        1,
        Icons.download,
        _downloads,
        AppLocalizations.settingsAutoStartDownloads,
      ),
      _e(
        1,
        Icons.download,
        _downloads,
        AppLocalizations.settingsAutoClipboardDetection,
      ),

      // Section 2: Quality & Format
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsMaxResolutionTitle,
      ),
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsVideoCodecTitle,
      ),
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsAudioCodecTitle,
      ),
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsContainerFormatTitle,
      ),
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsFrameRateTitle,
      ),
      _e(
        2,
        Icons.high_quality,
        _qualityFormat,
        AppLocalizations.settingsFormatPreferencesForceRemux,
      ),

      // Section 3: Media Processing
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsMediaEnhancementsDownloadThumbnail,
      ),
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsMediaEnhancementsEmbedThumbnail,
      ),
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsMediaEnhancementsEmbedMetadata,
      ),
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsMediaEnhancementsEmbedChapters,
      ),
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsSubtitlesDownloadSubtitles,
      ),
      _e(
        3,
        Icons.movie_filter,
        _mediaProcessing,
        AppLocalizations.settingsSponsorBlockSectionEnableSponsorBlock,
      ),

      // Section 4: Platforms
      _e(
        4,
        Icons.public,
        _platforms,
        AppLocalizations.settingsPlatformSpecificRemoveTikTokWatermark,
      ),

      // Section 5: Browser
      _e(5, Icons.language, _browser, AppLocalizations.adBlockToggle),
      _e(5, Icons.language, _browser, AppLocalizations.popupBlockerToggle),
      _e(5, Icons.language, _browser, AppLocalizations.phishingToggle),
      _e(5, Icons.language, _browser, AppLocalizations.httpsToggle),
      _e(5, Icons.language, _browser, AppLocalizations.fingerprintToggle),

      // Section 6: Network & Proxy
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.settingsNetworkAdvancedProxy,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.settingsNetworkAdvancedGeoBypass,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.settingsNetworkAdvancedArchiveMode,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.advancedOptionsSocketTimeout,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.advancedOptionsMaxRetries,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.advancedOptionsHttpChunkSize,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.advancedOptionsFilenameTemplate,
      ),
      _e(
        6,
        Icons.wifi,
        _networkProxy,
        AppLocalizations.advancedOptionsPostprocessorArgs,
      ),

      // Section 7: Engine & Components
      _e(
        7,
        Icons.engineering,
        _engineComponents,
        AppLocalizations.settingsDownloadEngine,
      ),
      _e(
        7,
        Icons.engineering,
        _engineComponents,
        AppLocalizations.settingsBinariesAutoUpdate,
      ),

      // Section 8: Premium
      _e(8, Icons.workspace_premium, _premium, AppLocalizations.premiumUpgrade),
      _e(
        8,
        Icons.workspace_premium,
        _premium,
        AppLocalizations.premiumActivateKey,
      ),
      _e(
        8,
        Icons.workspace_premium,
        _premium,
        AppLocalizations.premiumRestoreLicense,
      ),

      // Section 9: About & Support
      _e(
        9,
        Icons.info_outline,
        _aboutSupport,
        AppLocalizations.settingsAccountReportBug,
      ),
      _e(
        9,
        Icons.info_outline,
        _aboutSupport,
        AppLocalizations.settingsAccountRateApp,
      ),
      _e(
        9,
        Icons.info_outline,
        _aboutSupport,
        AppLocalizations.settingsResetToDefaults,
      ),
    ];
  }

  // Section label getters
  String get _general => AppLocalizations.settingsSectionGeneral;
  String get _downloads => AppLocalizations.settingsSectionDownloads;
  String get _qualityFormat => AppLocalizations.settingsSectionQualityFormat;
  String get _mediaProcessing =>
      AppLocalizations.settingsSectionMediaProcessing;
  String get _platforms => AppLocalizations.settingsSectionPlatforms;
  String get _browser => AppLocalizations.settingsSectionBrowser;
  String get _networkProxy => AppLocalizations.settingsSectionNetworkProxy;
  String get _engineComponents =>
      AppLocalizations.settingsSectionEngineComponents;
  String get _premium => AppLocalizations.premiumTitle;
  String get _aboutSupport => AppLocalizations.settingsSectionAboutSupport;

  SettingsSearchResult _e(
    int sectionIndex,
    IconData sectionIcon,
    String sectionLabel,
    String settingLabel,
  ) {
    return SettingsSearchResult(
      sectionIndex: sectionIndex,
      sectionLabel: sectionLabel,
      sectionIcon: sectionIcon,
      settingLabel: settingLabel,
    );
  }

  /// Search for settings matching [query].
  List<SettingsSearchResult> search(String query) {
    if (query.trim().isEmpty) return [];

    _cachedIndex ??= _buildIndex();

    final q = query.toLowerCase().trim();
    return _cachedIndex!.where((result) {
      if (result.settingLabel.toLowerCase().contains(q)) return true;
      if (result.sectionLabel.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  /// Returns section indices that contain at least one match.
  Set<int> matchingSectionIndices(String query) {
    return search(query).map((r) => r.sectionIndex).toSet();
  }

  /// Clear cached index (e.g. on locale change).
  void invalidateCache() {
    _cachedIndex = null;
  }
}
