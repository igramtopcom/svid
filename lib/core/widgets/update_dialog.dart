import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/brand_config.dart';
import '../constants/app_spacing.dart';
import '../l10n/app_localizations.dart';
import '../providers/backend_providers.dart';
import '../services/auto_update_service.dart';
import '../theme/app_colors.dart';

/// Full-featured update dialog with inline download progress.
///
/// Shows version comparison, release notes, and state-dependent actions:
/// - Idle: "Update Now" button to start download
/// - Downloading: animated progress bar with percentage and size
/// - Verifying: indeterminate progress spinner
/// - Ready: "Restart Now" button to apply update
/// - Failed: error message + "Retry" button
/// - Mandatory updates: non-dismissible, auto-starts download
class UpdateDialog extends ConsumerStatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? checksum;
  final bool isMandatory;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
    this.checksum,
    this.isMandatory = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    String? releaseNotes,
    String? downloadUrl,
    String? checksum,
    bool isMandatory = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder:
          (_) => UpdateDialog(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseNotes: releaseNotes,
            downloadUrl: downloadUrl,
            checksum: checksum,
            isMandatory: isMandatory,
          ),
    );
  }

  /// Show dialog from an UpdateCheckResponse provider state
  static Future<void> showFromProvider(BuildContext context, WidgetRef ref) {
    final update = ref.read(appUpdateProvider);
    if (update == null || !update.updateAvailable) return Future.value();

    return show(
      context,
      currentVersion: update.currentVersion,
      latestVersion: update.latestVersion ?? '',
      releaseNotes: update.releaseNotes,
      downloadUrl: update.downloadUrl,
      checksum: update.checksum,
      isMandatory: update.isMandatory,
    );
  }

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  bool _autoDownloadTriggered = false;

  bool get _canDownloadInApp =>
      BrandConfig.current.canAutoDownloadUpdate &&
      widget.downloadUrl != null &&
      widget.downloadUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Auto-start download for mandatory updates
    if (widget.isMandatory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startDownload(openWebsiteFallback: false);
      });
    }
  }

  void _startDownload({bool openWebsiteFallback = true}) {
    if (!_canDownloadInApp) {
      if (openWebsiteFallback) {
        _openWebsiteDownload();
      }
      return;
    }
    if (_autoDownloadTriggered) return;
    _autoDownloadTriggered = true;

    // Telemetry now fires from inside downloadUpdate AFTER the race
    // guard wins, so this site no longer emits. Pass `source:` instead
    // — the notifier maps it to the right funnel event.
    ref
        .read(autoUpdateProvider.notifier)
        .downloadUpdate(
          widget.downloadUrl!,
          widget.checksum ?? '',
          widget.latestVersion,
          source: widget.isMandatory ? 'mandatory_auto' : 'dialog_click',
        );
  }

  void _openWebsiteDownload() {
    final url = BrandConfig.current.websiteUrl;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(autoUpdateProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = _toneForStatus(context, updateState.status);
    final accent = tone.accent;
    final surface =
        isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest;

    return AlertDialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        side: BorderSide(color: accent.withValues(alpha: isDark ? 0.24 : 0.16)),
      ),
      icon: Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.container,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: tone.border),
        ),
        child: Icon(
          _iconForStatus(updateState.status),
          size: 30,
          color: accent,
        ),
      ),
      title: Text(
        _titleForStatus(updateState.status),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurface,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version comparison chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _versionChip(
                  context,
                  widget.currentVersion,
                  AppLocalizations.updateCurrent,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward_rounded, size: 20),
                ),
                _versionChip(
                  context,
                  widget.latestVersion,
                  AppLocalizations.updateLatest,
                  isLatest: true,
                ),
              ],
            ),

            // Mandatory warning
            if (widget.isMandatory) ...[
              const SizedBox(height: 16),
              _StatusNotice(
                icon: Icons.lock_clock_rounded,
                message: AppLocalizations.updateMandatory,
                tone: _UpdateTone.warning(context),
              ),
            ],

            // Download progress
            if (updateState.isDownloading ||
                updateState.status == UpdateStatus.verifying) ...[
              const SizedBox(height: 20),
              _buildProgressSection(context, updateState),
            ],

            // Error message
            if (updateState.isFailed && updateState.error != null) ...[
              const SizedBox(height: 16),
              _StatusNotice(
                icon: Icons.error_outline,
                message: updateState.error!,
                tone: _UpdateTone.error(context),
              ),
            ],

            // Ready to install success message
            if (updateState.isReady) ...[
              const SizedBox(height: 16),
              _StatusNotice(
                icon: Icons.check_circle_rounded,
                message: AppLocalizations.autoUpdateDownloadComplete,
                tone: _UpdateTone.success(context),
              ),
            ],

            // Installing message
            if (updateState.isInstalling) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.updatePreparingInstall),
                ],
              ),
            ],

            // Release notes
            if (widget.releaseNotes != null &&
                widget.releaseNotes!.isNotEmpty &&
                updateState.isIdle) ...[
              const SizedBox(height: 16),
              Text(
                AppLocalizations.updateWhatsNew,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.42),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.releaseNotes!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(context, updateState),
    );
  }

  Widget _buildProgressSection(BuildContext context, UpdateState state) {
    final isVerifying = state.status == UpdateStatus.verifying;
    final percent = (state.progress * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status text + percentage
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isVerifying
                  ? AppLocalizations.autoUpdateVerifying
                  : AppLocalizations.autoUpdateDownloading,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!isVerifying)
              Text(
                '$percent%',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: LinearProgressIndicator(
            value: isVerifying ? null : state.progress,
            minHeight: 6,
          ),
        ),
        // Size info
        if (!isVerifying && state.totalBytes > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${formatBytes(state.receivedBytes)} / ${formatBytes(state.totalBytes)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context, UpdateState state) {
    switch (state.status) {
      case UpdateStatus.idle:
        return [
          if (!widget.isMandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.updateLater),
            ),
          if (_canDownloadInApp)
            FilledButton.icon(
              onPressed: () => _startDownload(),
              icon: const Icon(Icons.download),
              label: Text(AppLocalizations.updateNow),
            )
          else
            FilledButton.icon(
              onPressed: _openWebsiteDownload,
              icon: const Icon(Icons.open_in_new),
              label: Text(AppLocalizations.updateDownloadUpdate),
            ),
        ];

      case UpdateStatus.downloading:
      case UpdateStatus.verifying:
        return [
          if (!widget.isMandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.autoUpdateDismiss),
            ),
        ];

      case UpdateStatus.readyToInstall:
        return [
          if (!widget.isMandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.updateLater),
            ),
          FilledButton.icon(
            onPressed: () {
              ref.read(autoUpdateProvider.notifier).installAndRestart();
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(AppLocalizations.updateRestartNow),
          ),
        ];

      case UpdateStatus.installing:
        return []; // No actions during install — app is about to exit

      case UpdateStatus.failed:
        return [
          if (!widget.isMandatory)
            TextButton(
              onPressed: () {
                ref.read(autoUpdateProvider.notifier).reset();
                Navigator.pop(context);
              },
              child: Text(AppLocalizations.updateLater),
            ),
          if (_canDownloadInApp)
            FilledButton.icon(
              onPressed: () {
                ref.read(autoUpdateProvider.notifier).reset();
                _autoDownloadTriggered = false;
                _startDownload();
              },
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.updateRetry),
            )
          else
            FilledButton.icon(
              onPressed: _openWebsiteDownload,
              icon: const Icon(Icons.open_in_new),
              label: Text(AppLocalizations.updateDownloadUpdate),
            ),
        ];
    }
  }

  IconData _iconForStatus(UpdateStatus status) {
    return switch (status) {
      UpdateStatus.idle => Icons.system_update_alt,
      UpdateStatus.downloading => Icons.downloading,
      UpdateStatus.verifying => Icons.verified_user,
      UpdateStatus.readyToInstall => Icons.check_circle_rounded,
      UpdateStatus.installing => Icons.install_desktop,
      UpdateStatus.failed => Icons.error_outline,
    };
  }

  _UpdateTone _toneForStatus(BuildContext context, UpdateStatus status) {
    return switch (status) {
      UpdateStatus.readyToInstall => _UpdateTone.success(context),
      UpdateStatus.failed => _UpdateTone.error(context),
      UpdateStatus.downloading ||
      UpdateStatus.verifying ||
      UpdateStatus.installing => _UpdateTone.info(context),
      UpdateStatus.idle => _UpdateTone.brand(context),
    };
  }

  String _titleForStatus(UpdateStatus status) {
    return switch (status) {
      UpdateStatus.idle => AppLocalizations.updateAvailable,
      UpdateStatus.downloading => AppLocalizations.autoUpdateDownloading,
      UpdateStatus.verifying => AppLocalizations.autoUpdateVerifying,
      UpdateStatus.readyToInstall => AppLocalizations.autoUpdateReadyToInstall,
      UpdateStatus.installing => AppLocalizations.autoUpdateInstalling,
      UpdateStatus.failed => AppLocalizations.autoUpdateFailed,
    };
  }

  Widget _versionChip(
    BuildContext context,
    String version,
    String label, {
    bool isLatest = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = isLatest ? cs.primary : cs.outline;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color:
                isLatest
                    ? cs.primary.withValues(alpha: 0.10)
                    : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Text(
            'v$version',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: isLatest ? cs.primary : cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final _UpdateTone tone;

  const _StatusNotice({
    required this.icon,
    required this.message,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tone.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateTone {
  final Color accent;
  final Color container;
  final Color border;
  final Color text;

  const _UpdateTone({
    required this.accent,
    required this.container,
    required this.border,
    required this.text,
  });

  factory _UpdateTone.brand(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = cs.primary;
    return _UpdateTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.18 : 0.10),
      border: accent.withValues(alpha: isDark ? 0.28 : 0.18),
      text: cs.onSurface,
    );
  }

  factory _UpdateTone.info(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.info(context);
    return _UpdateTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.16 : 0.09),
      border: accent.withValues(alpha: isDark ? 0.30 : 0.20),
      text: Theme.of(context).colorScheme.onSurface,
    );
  }

  factory _UpdateTone.success(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.success(context);
    return _UpdateTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.16 : 0.10),
      border: accent.withValues(alpha: isDark ? 0.32 : 0.22),
      text: Theme.of(context).colorScheme.onSurface,
    );
  }

  factory _UpdateTone.warning(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.warning(context);
    return _UpdateTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.14 : 0.10),
      border: accent.withValues(alpha: isDark ? 0.30 : 0.22),
      text: Theme.of(context).colorScheme.onSurface,
    );
  }

  factory _UpdateTone.error(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = cs.error;
    return _UpdateTone(
      accent: accent,
      container: cs.errorContainer.withValues(alpha: isDark ? 0.44 : 1),
      border: accent.withValues(alpha: isDark ? 0.32 : 0.22),
      text: cs.onErrorContainer,
    );
  }
}
