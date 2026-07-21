import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../data/datasources/ffmpeg_datasource.dart';
import '../providers/trim_providers.dart';

/// Dialog for configuring and executing a video trim export.
///
/// Shows mode selection, progress bar during export, and success/error states.
class TrimExportDialog extends ConsumerStatefulWidget {
  final DownloadEntity video;
  final Duration startTime;
  final Duration endTime;

  const TrimExportDialog({
    super.key,
    required this.video,
    required this.startTime,
    required this.endTime,
  });

  /// Show the dialog
  static Future<void> show(
    BuildContext context, {
    required DownloadEntity video,
    required Duration startTime,
    required Duration endTime,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => TrimExportDialog(
            video: video,
            startTime: startTime,
            endTime: endTime,
          ),
    );
  }

  @override
  ConsumerState<TrimExportDialog> createState() => _TrimExportDialogState();
}

enum _DialogState { idle, exporting, completed, error }

class _TrimExportDialogState extends ConsumerState<TrimExportDialog> {
  TrimMode _mode = TrimMode.fast;
  _DialogState _state = _DialogState.idle;
  double _progress = 0;
  Duration _processed = Duration.zero;
  String? _outputPath;
  String? _errorMessage;

  Duration get _trimDuration => widget.endTime - widget.startTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius.dialog,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            _buildTitleBar(theme),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time info
                    _buildTimeInfo(theme),
                    const SizedBox(height: 16),

                    // Mode selection (only when idle)
                    if (_state == _DialogState.idle) ...[
                      _buildModeSelection(theme),
                      const SizedBox(height: 16),
                      _buildOutputInfo(theme),
                    ],

                    // Progress (when exporting)
                    if (_state == _DialogState.exporting) _buildProgress(theme),

                    // Completed
                    if (_state == _DialogState.completed)
                      _buildCompleted(theme),

                    // Error
                    if (_state == _DialogState.error) _buildError(theme),
                  ],
                ),
              ),
            ),

            // Action bar
            _buildActionBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.content_cut, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Trim Video',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_state != _DialogState.exporting)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildTimeInfo(ThemeData theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildTimeChip(theme, 'From', widget.startTime),
        Icon(
          Icons.arrow_forward,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildTimeChip(theme, 'To', widget.endTime),
        Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadius.borderRadius.card,
            ),
            child: Text(
              _formatDuration(_trimDuration),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeChip(ThemeData theme, String label, Duration time) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          _formatDuration(time),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        _buildModeOption(
          theme,
          mode: TrimMode.fast,
          title: AppLocalizations.playerTrimFastTitle,
          subtitle: AppLocalizations.playerTrimFastSubtitle,
          icon: Icons.bolt,
        ),
        const SizedBox(height: 6),
        _buildModeOption(
          theme,
          mode: TrimMode.precise,
          title: AppLocalizations.playerTrimPreciseTitle,
          subtitle: AppLocalizations.playerTrimPreciseSubtitle,
          icon: Icons.high_quality,
        ),
      ],
    );
  }

  Widget _buildModeOption(
    ThemeData theme, {
    required TrimMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: AppRadius.borderRadius.card,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withAlpha(77),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: AppRadius.borderRadius.card,
          color: isSelected ? theme.colorScheme.primary.withAlpha(20) : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color:
                  isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputInfo(ThemeData theme) {
    final ext = widget.video.fileExtension;
    final baseName = widget.video.filenameWithoutExtension;
    return Row(
      children: [
        Icon(Icons.output, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$baseName (trimmed)$ext',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _progress,
          minHeight: 6,
          borderRadius: AppRadius.borderRadius.card,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Processing: ${_formatDuration(_processed)} / ${_formatDuration(_trimDuration)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompleted(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(20),
        borderRadius: AppRadius.borderRadius.card,
        border: Border.all(color: Colors.green.withAlpha(77)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trim completed!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          if (_outputPath != null) ...[
            const SizedBox(height: 8),
            Text(
              p.basename(_outputPath!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: AppRadius.borderRadius.card,
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? 'Unknown error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (_state == _DialogState.idle) ...[
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.commonCancel),
            ),
            FilledButton.icon(
              onPressed: _startExport,
              icon: const Icon(Icons.content_cut),
              label: Text(AppLocalizations.playerTrimExport),
            ),
          ],
          if (_state == _DialogState.exporting)
            OutlinedButton(
              onPressed: _cancelExport,
              child: Text(AppLocalizations.commonCancel),
            ),
          if (_state == _DialogState.completed) ...[
            if (_outputPath != null)
              OutlinedButton.icon(
                onPressed: _showInFinder,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(AppLocalizations.playerTrimShowInFinder),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.playerDone),
            ),
          ],
          if (_state == _DialogState.error) ...[
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.playerClose),
            ),
            FilledButton(
              onPressed: () => setState(() => _state = _DialogState.idle),
              child: Text(AppLocalizations.commonRetry),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startExport() async {
    setState(() {
      _state = _DialogState.exporting;
      _progress = 0;
      _processed = Duration.zero;
    });

    final useCase = ref.read(trimVideoUseCaseProvider);

    await for (final progress in useCase.call(
      video: widget.video,
      startTime: widget.startTime,
      endTime: widget.endTime,
      mode: _mode,
    )) {
      if (!mounted) return;

      switch (progress.status) {
        case TrimStatus.starting:
          // Already showing progress UI
          break;
        case TrimStatus.processing:
          setState(() {
            _progress = progress.percent;
            _processed = progress.processed;
          });
          break;
        case TrimStatus.completed:
          setState(() {
            _state = _DialogState.completed;
            _outputPath = progress.outputPath;
            _progress = 1.0;
          });
          break;
        case TrimStatus.error:
          setState(() {
            _state = _DialogState.error;
            _errorMessage = progress.error;
          });
          break;
        case TrimStatus.cancelled:
          if (mounted) Navigator.pop(context);
          break;
      }
    }
  }

  void _cancelExport() {
    ref.read(trimVideoUseCaseProvider).cancel();
  }

  void _showInFinder() {
    if (_outputPath == null) return;
    final dir = File(_outputPath!).parent.path;
    if (Platform.isMacOS) {
      ProcessHelper.revealInFileManager(
        _outputPath!,
        fallbackDirectory: dir,
      ).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.revealInFileManager(
        _outputPath!,
        fallbackDirectory: dir,
      ).ignore();
    } else {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    }
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
