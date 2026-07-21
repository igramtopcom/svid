import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_config.dart';

Future<void> persistDownloadConfigDefaults({
  required SettingsNotifier notifier,
  required SettingsState settings,
  required DownloadConfig config,
}) async {
  final savePathOverride = config.savePathOverride;
  if (savePathOverride != null && savePathOverride.isNotEmpty) {
    await notifier.updateDownloadPath(savePathOverride);
  }
  final canPersistPrimarySelection =
      config.qualityIntent != DownloadQualityIntent.technicalStream;
  if (canPersistPrimarySelection &&
      (config.fileType != null ||
          config.qualityIntent != settings.defaultDownloadQualityIntent ||
          config.qualityTarget != null)) {
    await notifier.updateDefaultDownloadSelection(
      fileType: config.fileType ?? settings.defaultDownloadFileType,
      qualityIntent: config.qualityIntent,
      qualityTarget: config.qualityTarget,
    );
  }
  if (config.videoCodecOverride != null) {
    await notifier.updateVideoCodecPreference(config.videoCodecOverride!);
  }
  if (config.audioCodecOverride != null) {
    await notifier.updateAudioCodecPreference(config.audioCodecOverride!);
  }
  if (config.containerFormatOverride != null) {
    await notifier.updateContainerFormatPreference(
      config.containerFormatOverride!,
    );
  }
  if (config.fpsOverride != null) {
    await notifier.updateFpsPreference(config.fpsOverride!);
  }
  if (config.maxResolutionOverride != null) {
    await notifier.updateMaxResolution(config.maxResolutionOverride!);
  }
  if (config.subtitlesEnabled != null &&
      config.subtitlesEnabled != settings.subtitlesEnabled) {
    await notifier.toggleSubtitles();
  }
  if (config.subtitlesLanguages != null) {
    await notifier.updateSubtitlesLanguages(config.subtitlesLanguages!);
  }
  if (config.subtitlesFormat != null) {
    await notifier.updateSubtitlesFormat(config.subtitlesFormat!);
  }
  if (config.includeAutoSubs != null &&
      config.includeAutoSubs != settings.includeAutoSubs) {
    await notifier.toggleIncludeAutoSubs();
  }
  if (config.embedSubtitles != null &&
      config.embedSubtitles != settings.embedSubtitles) {
    await notifier.toggleEmbedSubtitles();
  }
  if (config.writeThumbnail != null &&
      config.writeThumbnail != settings.writeThumbnail) {
    await notifier.toggleWriteThumbnail();
  }
  if (config.embedThumbnail != null &&
      config.embedThumbnail != settings.embedThumbnail) {
    await notifier.toggleEmbedThumbnail();
  }
  if (config.embedMetadata != null &&
      config.embedMetadata != settings.embedMetadata) {
    await notifier.toggleEmbedMetadata();
  }
  if (config.embedChapters != null &&
      config.embedChapters != settings.embedChapters) {
    await notifier.toggleEmbedChapters();
  }
  if (config.sponsorBlockEnabled != null &&
      config.sponsorBlockEnabled != settings.sponsorBlockEnabled) {
    await notifier.toggleSponsorBlock();
  }
  if (config.sponsorBlockAction != null) {
    await notifier.updateSponsorBlockAction(config.sponsorBlockAction!);
  }
  if (config.sponsorBlockCategories != null) {
    await notifier.updateSponsorBlockCategories(config.sponsorBlockCategories!);
  }
  if (config.forceRemux != null && config.forceRemux != settings.forceRemux) {
    await notifier.toggleForceRemux();
  }
  if (config.tiktokRemoveWatermark != null &&
      config.tiktokRemoveWatermark != settings.tiktokRemoveWatermark) {
    await notifier.toggleTiktokRemoveWatermark();
  }
}
