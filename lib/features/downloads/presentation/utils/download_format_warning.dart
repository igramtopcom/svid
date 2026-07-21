import '../../../../core/core.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_config.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/format_selector_service.dart';
import '../../domain/services/quality_resolution_parser.dart';

String? downloadFormatWarningMessage({
  required Quality quality,
  required DownloadConfig? config,
  required SettingsState settings,
}) {
  final warning = downloadFormatWarning(
    quality: quality,
    config: config,
    settings: settings,
  );
  if (warning == null) return null;

  return formatSelectionWarningMessage(warning);
}

String? formatSelectionWarningMessageOrNull(FormatSelectionWarning? warning) {
  return warning == null ? null : formatSelectionWarningMessage(warning);
}

String formatSelectionWarningMessage(FormatSelectionWarning warning) {
  switch (warning.code) {
    case FormatSelectionWarningCode.containerChanged:
      return AppLocalizations.configDialogContainerChangedWarning(
        warning.requestedLabel,
        warning.resolvedLabel ?? '',
      );
    case FormatSelectionWarningCode.exactUnavailable:
      return AppLocalizations.configDialogQualityFallbackWarning(
        warning.requestedLabel,
        warning.resolvedLabel ?? '',
      );
    case FormatSelectionWarningCode.authRequired:
      return AppLocalizations.configDialogBestAvailableAuthRequired;
    case FormatSelectionWarningCode.formatUnavailable:
      return warning.resolvedLabel == null
          ? AppLocalizations.errorFeedbackHint('formatUnavailable')
          : AppLocalizations.configDialogQualityFallbackWarning(
            warning.requestedLabel,
            warning.resolvedLabel!,
          );
  }
}

String? combineDownloadWarnings(Iterable<String?> warnings) {
  final uniqueWarnings = <String>[];
  for (final warning in warnings) {
    if (warning == null || warning.trim().isEmpty) continue;
    if (!uniqueWarnings.contains(warning)) uniqueWarnings.add(warning);
  }
  return uniqueWarnings.isEmpty ? null : uniqueWarnings.join(' ');
}

FormatSelectionWarning? downloadFormatWarning({
  required Quality quality,
  required DownloadConfig? config,
  required SettingsState settings,
  FormatSelectorService selector = const FormatSelectorService(),
}) {
  if (!quality.encryptedUrl.startsWith('ytdlp:') ||
      quality.mediaType != MediaType.video) {
    return null;
  }

  final fileType =
      config?.fileType ?? DownloadFileType.fromMediaType(quality.mediaType);
  final isBestAvailable =
      config?.qualityIntent == DownloadQualityIntent.bestAvailable ||
      quality.encryptedUrl == 'ytdlp:best:mp4';
  if (!isBestAvailable || fileType != DownloadFileType.video) return null;

  final selectedHeight = QualityResolutionParser.heightForQuality(quality);
  return selector
      .buildSelection(
        FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.bestAvailable,
          fileType: fileType,
          target:
              selectedHeight == null
                  ? null
                  : PortableQualityTarget.video(targetHeight: selectedHeight),
          videoCodecPreference:
              config?.resolveVideoCodec(settings) ??
              settings.videoCodecPreference,
          audioCodecPreference:
              config?.resolveAudioCodec(settings) ??
              settings.audioCodecPreference,
          containerFormatPreference:
              config?.resolveContainerFormat(settings) ??
              settings.containerFormatPreference,
          fpsPreference: config?.resolveFps(settings) ?? settings.fpsPreference,
          forceRemuxPreference:
              config?.resolveForceRemux(settings) ?? settings.forceRemux,
        ),
      )
      .warning;
}
