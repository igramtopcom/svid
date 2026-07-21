import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// Panel for adding files to convert: drag & drop zone, file picker,
/// and "From Downloads" button.
class AddFilesPanel extends ConsumerStatefulWidget {
  final void Function(List<String> filePaths) onFilesSelected;

  const AddFilesPanel({super.key, required this.onFilesSelected});

  @override
  ConsumerState<AddFilesPanel> createState() => _AddFilesPanelState();
}

class _AddFilesPanelState extends ConsumerState<AddFilesPanel> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DropTarget(
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final paths =
            details.files
                .where((f) => _isSupportedFile(f.path))
                .map((f) => f.path)
                .toList();
        if (paths.isNotEmpty) {
          widget.onFilesSelected(paths);
        }
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        decoration: BoxDecoration(
          color:
              _isDragging
                  ? AppColors.accentHighlight.withValues(alpha: 0.07)
                  : AppColors.surface2(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                _isDragging
                    ? AppColors.accentHighlight.withValues(alpha: 0.45)
                    : (isDark
                        ? AppColors.homeDarkBorderStrong
                        : AppColors.border(context).withValues(alpha: 0.55)),
          ),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color:
                _isDragging
                    ? AppColors.accentHighlight
                    : (isDark
                        ? AppColors.homeDarkBorderStrong
                        : Colors.transparent),
            strokeWidth: _isDragging ? 1.6 : 1.1,
            dashWidth: 6,
            dashGap: 4,
            radius: 3,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drop zone icon — framed rail
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        _isDragging
                            ? AppColors.accentHighlight.withValues(alpha: 0.15)
                            : (isDark
                                ? AppColors.homeDarkCardHover
                                : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                )),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color:
                          _isDragging
                              ? AppColors.accentHighlight.withValues(alpha: 0.5)
                              : (isDark
                                  ? AppColors.homeDarkBorderSubtle
                                  : cs.outlineVariant.withValues(alpha: 0.15)),
                    ),
                  ),
                  child: Icon(
                    _isDragging
                        ? Icons.file_download_rounded
                        : Icons.upload_file_rounded,
                    size: 20,
                    color:
                        _isDragging
                            ? AppColors.accentHighlight
                            : cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isDragging
                      ? 'converter.releaseToLoad'.tr()
                      : 'converter.dropFilesHere'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    color:
                        _isDragging
                            ? AppColors.accentHighlight
                            : (isDark
                                ? AppColors.darkLightText
                                : cs.onSurface.withValues(alpha: 0.85)),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isDragging
                      ? 'converter.fileWillBeAnalyzed'.tr()
                      : 'converter.pickFromDeviceHint'.tr(),
                  style: tt.labelSmall?.copyWith(
                    color:
                        isDark
                            ? AppColors.homeDarkTextSecondary
                            : cs.onSurfaceVariant.withValues(alpha: 0.65),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),

                // Supported format pills — 3 clusters
                _FormatPillRow(
                  clusters: [
                    (
                      'converter.categoryVideoLabel'.tr(),
                      'MP4 MKV MOV AVI WEBM',
                    ),
                    ('converter.categoryAudioLabel'.tr(), 'MP3 FLAC WAV OPUS'),
                    ('converter.categoryImgLabel'.tr(), 'GIF WEBP'),
                  ],
                ),
                const SizedBox(height: 12),

                // Divider
                Container(
                  height: 1,
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : cs.outlineVariant.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 10),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ActionButton(
                      icon: Icons.folder_open_rounded,
                      label: 'converter.pickFiles'.tr(),
                      onTap: () => _pickFiles(context),
                      color: AppColors.accentHighlight,
                      isPrimary: true,
                    ),
                    const SizedBox(width: 10),
                    _ActionButton(
                      icon: Icons.download_done_rounded,
                      label: 'converter.fromDownloads'.tr(),
                      onTap: () => _pickFromDownloads(context, ref),
                      color: cs.onSurfaceVariant,
                      isPrimary: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSupportedFile(String path) {
    final ext = p.extension(path).toLowerCase().replaceAll('.', '');
    return _supportedExtensions.contains(ext);
  }

  Future<void> _pickFiles(BuildContext context) async {
    try {
      final downloadDir = ref.read(downloadPathProvider);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: true,
        dialogTitle: 'converter.selectFilesDialog'.tr(),
        initialDirectory: downloadDir,
      );
      if (!mounted) return;

      if (result != null && result.files.isNotEmpty) {
        final paths =
            result.files
                .where((f) => f.path != null)
                .map((f) => f.path!)
                .toList();
        if (paths.isNotEmpty) {
          widget.onFilesSelected(paths);
        }
      }
    } catch (e) {
      // FilePicker can throw on some platforms
      if (context.mounted) {
        AppSnackBar.error(
          context,
          message: 'converter.filePickerFailed'.tr(namedArgs: {'error': '$e'}),
        );
      }
    }
  }

  Future<void> _pickFromDownloads(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      final completedDownloads = await db.getDownloadsByStatus('completed');

      if (completedDownloads.isEmpty) {
        if (context.mounted) {
          AppSnackBar.info(
            context,
            message: 'converter.noCompletedDownloads'.tr(),
          );
        }
        return;
      }

      if (!context.mounted) return;

      final selectedPaths = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => _DownloadPickerDialog(downloads: completedDownloads),
      );
      if (!mounted) return;

      if (selectedPaths != null && selectedPaths.isNotEmpty) {
        widget.onFilesSelected(selectedPaths);
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.error(
          context,
          message: 'converter.failedToLoadDownloads'.tr(
            namedArgs: {'error': '$e'},
          ),
        );
      }
    }
  }

  static const _supportedExtensions = [
    // Video
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'ts', 'flv', 'wmv', 'mpg', 'mpeg',
    'm4v', '3gp', 'ogv',
    // Audio
    'mp3', 'aac', 'flac', 'wav', 'ogg', 'opus', 'm4a', 'wma', 'aiff',
    // Animated
    'gif', 'webp',
  ];
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg =
        isPrimary
            ? color.withValues(alpha: 0.14)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5);
    final borderColor =
        isPrimary
            ? color.withValues(alpha: 0.55)
            : cs.outlineVariant.withValues(alpha: 0.15);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Format pill row: `[VIDEO] MP4 MKV MOV · [AUDIO] MP3 FLAC · [IMG] GIF`.
class _FormatPillRow extends StatelessWidget {
  final List<(String, String)> clusters;
  const _FormatPillRow({required this.clusters});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        for (int i = 0; i < clusters.length; i++) ...[
          _FormatCluster(
            label: clusters[i].$1,
            formats: clusters[i].$2,
            baseColor: cs.onSurfaceVariant,
          ),
          if (i < clusters.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 2,
                height: 2,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _FormatCluster extends StatelessWidget {
  final String label;
  final String formats;
  final Color baseColor;

  const _FormatCluster({
    required this.label,
    required this.formats,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: baseColor.withValues(alpha: 0.55),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: formats,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: baseColor.withValues(alpha: 0.85),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter that draws a dashed rounded-rectangle border around its child area.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;
  final double radius;

  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashGap,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) {
    return old.color != color ||
        old.strokeWidth != strokeWidth ||
        old.dashWidth != dashWidth ||
        old.dashGap != dashGap ||
        old.radius != radius;
  }
}

/// Dialog showing completed downloads for user to select files to convert.
/// Filters out missing files upfront so the picker stays focused on usable
/// conversion inputs.
class _DownloadPickerDialog extends StatefulWidget {
  final List<Download> downloads;

  const _DownloadPickerDialog({required this.downloads});

  @override
  State<_DownloadPickerDialog> createState() => _DownloadPickerDialogState();
}

class _DownloadPickerDialogState extends State<_DownloadPickerDialog> {
  final Set<int> _selectedIndices = {};
  late final List<Download> _existing;
  late final int _missingCount;

  @override
  void initState() {
    super.initState();
    // Partition once: existing files shown, missing files hidden but counted
    // so the user still knows why some downloads aren't listed.
    final existing = <Download>[];
    var missing = 0;
    for (final dl in widget.downloads) {
      if (File(p.join(dl.savePath, dl.filename)).existsSync()) {
        existing.add(dl);
      } else {
        missing++;
      }
    }
    _existing = existing;
    _missingCount = missing;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tt = Theme.of(context).textTheme;

    final bg = AppColors.surface1(context);
    final hairline =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.60);
    final primaryText =
        isDark
            ? AppColors.darkLightText
            : Theme.of(context).colorScheme.onSurface;
    final metaText =
        isDark
            ? AppColors.homeDarkTextSecondary
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: AppColors.accentHighlight.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(primaryText, metaText, hairline),
            Flexible(
              child:
                  _existing.isEmpty
                      ? _buildEmptyState(primaryText, metaText)
                      : _buildList(tt, primaryText, metaText, hairline, isDark),
            ),
            if (_existing.isNotEmpty && _missingCount > 0)
              _buildMissingHint(metaText, hairline),
            _buildActions(hairline),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color primary, Color meta, Color hairline) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hairline, width: 1)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 18, color: AppColors.accentHighlight),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Text(
              'converter.selectDownloadsDialog'.tr(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: primary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: meta),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'converter.cancel'.tr(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color primary, Color meta) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 44,
            color: meta.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'converter.allDownloadsMissing'.tr(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'converter.allDownloadsMissingHint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: meta, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    TextTheme tt,
    Color primary,
    Color meta,
    Color hairline,
    bool isDark,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _existing.length,
      separatorBuilder:
          (_, __) => Divider(height: 1, thickness: 1, color: hairline),
      itemBuilder: (context, index) {
        final dl = _existing[index];
        final isSelected = _selectedIndices.contains(index);
        final ext = p.extension(dl.filename).toUpperCase().replaceAll('.', '');

        return InkWell(
          onTap:
              () => setState(() {
                if (isSelected) {
                  _selectedIndices.remove(index);
                } else {
                  _selectedIndices.add(index);
                }
              }),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.smMd,
            ),
            color:
                isSelected
                    ? AppColors.accentHighlight.withValues(alpha: 0.08)
                    : Colors.transparent,
            child: Row(
              children: [
                _SquareCheckbox(checked: isSelected),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dl.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            ext,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                              color: AppColors.accentHighlight,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            String.fromCharCode(0x2022),
                            style: TextStyle(color: meta, fontSize: 10),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            _formatBytes(dl.totalBytes),
                            style: TextStyle(
                              fontSize: 11,
                              color: meta,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissingHint(Color meta, Color hairline) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hairline, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: meta),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'converter.missingFilesHint'.tr(
                namedArgs: {'count': '$_missingCount'},
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: meta, letterSpacing: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(Color hairline) {
    final hasSelection = _selectedIndices.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hairline, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('converter.cancel'.tr()),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed:
                hasSelection
                    ? () {
                      final paths =
                          _selectedIndices
                              .map(
                                (i) => p.join(
                                  _existing[i].savePath,
                                  _existing[i].filename,
                                ),
                              )
                              .toList();
                      Navigator.of(context).pop(paths);
                    }
                    : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentHighlight,
              disabledBackgroundColor: AppColors.accentHighlight.withValues(
                alpha: 0.25,
              ),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.smMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
            child: Text(
              'converter.selectN'.tr(
                namedArgs: {'count': '${_selectedIndices.length}'},
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Square checkbox styled for Noir — more architectural than Material's
/// default rounded square, matching the wine-accent vocabulary.
class _SquareCheckbox extends StatelessWidget {
  final bool checked;

  const _SquareCheckbox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? AppColors.accentHighlight : Colors.transparent,
        border: Border.all(
          color:
              checked
                  ? AppColors.accentHighlight
                  : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.35),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child:
          checked
              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
              : null,
    );
  }
}
