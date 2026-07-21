import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../downloads/domain/entities/download_selection_intent.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../domain/entities/platform_quality_preference.dart';
import 'settings_provider.dart';

/// State for platform quality preferences
class PlatformPreferencesState {
  final Map<VideoPlatform, PlatformQualityPreference> preferences;
  final bool isLoading;

  const PlatformPreferencesState({
    required this.preferences,
    this.isLoading = false,
  });

  PlatformPreferencesState copyWith({
    Map<VideoPlatform, PlatformQualityPreference>? preferences,
    bool? isLoading,
  }) {
    return PlatformPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Notifier for managing platform quality preferences
class PlatformPreferencesNotifier
    extends StateNotifier<PlatformPreferencesState> {
  final SettingsLocalDatasource _datasource;

  PlatformPreferencesNotifier(this._datasource)
    : super(const PlatformPreferencesState(preferences: {})) {
    _load();
  }

  /// Load saved preferences from storage
  Future<void> _load() async {
    try {
      final preferences = _datasource.getPlatformPreferences();
      state = state.copyWith(preferences: preferences);
      appLogger.info('📥 Loaded ${preferences.length} platform preferences');
    } catch (e, stack) {
      appLogger.error('Failed to load platform preferences', e, stack);
    }
  }

  /// Get preference for a specific platform
  PlatformQualityPreference? getPreference(VideoPlatform platform) {
    return state.preferences[platform];
  }

  /// Save preference for a platform with optional format overrides
  Future<void> savePreference({
    required VideoPlatform platform,
    required String qualityText,
    required MediaType mediaType,
    DownloadFileType? fileType,
    DownloadQualityIntent? qualityIntent,
    PortableQualityTarget? qualityTarget,
    // Format overrides (null = don't save, use global default)
    String? videoCodec,
    String? audioCodec,
    String? containerFormat,
    String? fpsPreference,
    int? maxResolution,
    bool? subtitlesEnabled,
    List<String>? subtitlesLanguages,
    String? subtitlesFormat,
    bool? embedSubtitles,
    bool? includeAutoSubs,
    bool? writeThumbnail,
    bool? sponsorBlockEnabled,
    String? sponsorBlockAction,
    List<String>? sponsorBlockCategories,
    bool? forceRemux,
    bool? tiktokRemoveWatermark,
    bool? embedThumbnail,
    bool? embedMetadata,
    bool? embedChapters,
  }) async {
    try {
      if (qualityIntent == DownloadQualityIntent.technicalStream) {
        appLogger.info(
          'Skipping platform preference save for non-portable technical stream',
        );
        return;
      }
      final preference = PlatformQualityPreference(
        platform: platform,
        qualityText: qualityText,
        mediaType: mediaType,
        savedAt: DateTime.now(),
        fileType: fileType,
        qualityIntent: qualityIntent,
        qualityTarget: qualityTarget,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        containerFormat: containerFormat,
        fpsPreference: fpsPreference,
        maxResolution: maxResolution,
        subtitlesEnabled: subtitlesEnabled,
        subtitlesLanguages: subtitlesLanguages,
        subtitlesFormat: subtitlesFormat,
        embedSubtitles: embedSubtitles,
        includeAutoSubs: includeAutoSubs,
        writeThumbnail: writeThumbnail,
        sponsorBlockEnabled: sponsorBlockEnabled,
        sponsorBlockAction: sponsorBlockAction,
        sponsorBlockCategories: sponsorBlockCategories,
        forceRemux: forceRemux,
        tiktokRemoveWatermark: tiktokRemoveWatermark,
        embedThumbnail: embedThumbnail,
        embedMetadata: embedMetadata,
        embedChapters: embedChapters,
      );

      await _datasource.savePlatformPreference(platform, preference);

      final updatedPreferences =
          Map<VideoPlatform, PlatformQualityPreference>.from(state.preferences);
      updatedPreferences[platform] = preference;

      state = state.copyWith(preferences: updatedPreferences);

      appLogger.info(
        '💾 Saved preference for ${platform.displayName}: $qualityText',
      );
    } catch (e, stack) {
      appLogger.error('Failed to save platform preference', e, stack);
    }
  }

  /// Remove preference for a platform
  Future<void> removePreference(VideoPlatform platform) async {
    try {
      await _datasource.removePlatformPreference(platform);

      final updatedPreferences =
          Map<VideoPlatform, PlatformQualityPreference>.from(state.preferences);
      updatedPreferences.remove(platform);

      state = state.copyWith(preferences: updatedPreferences);

      appLogger.info('🗑️ Removed preference for ${platform.displayName}');
    } catch (e, stack) {
      appLogger.error('Failed to remove platform preference', e, stack);
    }
  }

  /// Clear all preferences
  Future<void> clearAll() async {
    try {
      await _datasource.clearAllPlatformPreferences();
      state = state.copyWith(preferences: {});
      appLogger.info('🗑️ Cleared all platform preferences');
    } catch (e, stack) {
      appLogger.error('Failed to clear platform preferences', e, stack);
    }
  }
}

/// Provider for platform preferences notifier
final platformPreferencesProvider = StateNotifierProvider<
  PlatformPreferencesNotifier,
  PlatformPreferencesState
>((ref) {
  final datasource = ref.watch(settingsLocalDatasourceProvider);
  return PlatformPreferencesNotifier(datasource);
});
