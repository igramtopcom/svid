import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/media_info.dart';
import '../providers/conversion_queue_provider.dart';
import '../providers/converter_providers.dart';
import '../widgets/editor_canvas.dart';
import '../widgets/editor_properties_panel.dart';

/// Standalone editor screen — two-panel tabbed layout for editing files
/// that aren't currently playing in the video player.
///
/// Layout: [Canvas Preview] | [Tabbed Properties Panel]
///
/// Entry points:
/// 1. From Forge: "Open in Editor" button
/// 2. From Downloads: right-click context menu → "Edit"
class EditorScreen extends ConsumerStatefulWidget {
  /// Path to the media file to edit.
  final String filePath;

  /// Pre-probed media info (optional — will probe if null).
  final MediaInfo? mediaInfo;

  const EditorScreen({super.key, required this.filePath, this.mediaInfo});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  MediaInfo? _mediaInfo;
  bool _isProbing = false;
  String? _outputDir;
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _mediaInfo = widget.mediaInfo;
    if (_mediaInfo == null) {
      _probeFile();
    } else {
      _extractThumbnail();
    }
  }

  Future<void> _probeFile() async {
    setState(() => _isProbing = true);
    try {
      final probeUseCase = ref.read(probeMediaUseCaseProvider);
      final result = await probeUseCase.call(widget.filePath);
      result.when(
        success: (info) {
          if (mounted) {
            setState(() => _mediaInfo = info);
            _extractThumbnail();
          }
        },
        failure: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${'converter.probeFailed'.tr()}: $error'),
              ),
            );
          }
        },
      );
    } catch (e) {
      appLogger.error('[Editor] Probe failed', e);
    }
    if (mounted) setState(() => _isProbing = false);
  }

  Future<void> _extractThumbnail() async {
    if (_mediaInfo == null || !_mediaInfo!.hasVideo) return;
    try {
      final datasource = ref.read(conversionDatasourceProvider);
      final thumbPath = await datasource.getOrExtractInputThumbnail(
        widget.filePath,
      );
      if (mounted && thumbPath != null) {
        setState(() => _thumbnailPath = thumbPath);
      }
    } catch (e) {
      appLogger.debug('[Editor] Thumbnail extraction failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNarrow = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: AppColors.surface1(context),
      body: Column(
        children: [
          // Top header bar
          _buildHeader(cs),

          if (isNarrow) ...[
            // Narrow layout: stacked canvas + tabbed properties
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 35,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: EditorCanvas(
                        filePath: widget.filePath,
                        mediaInfo: _mediaInfo,
                        isProbing: _isProbing,
                        thumbnailPath: _thumbnailPath,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 65,
                    child: EditorPropertiesPanel(mediaInfo: _mediaInfo),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Wide layout: 2-panel (canvas | tabbed properties)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 55,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: EditorCanvas(
                        filePath: widget.filePath,
                        mediaInfo: _mediaInfo,
                        isProbing: _isProbing,
                        thumbnailPath: _thumbnailPath,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 45,
                    child: EditorPropertiesPanel(mediaInfo: _mediaInfo),
                  ),
                ],
              ),
            ),
          ],

          // Bottom action bar
          _buildBottomBar(cs),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final filename = File(widget.filePath).uri.pathSegments.last;

    return Container(
      height: 48,
      padding: EdgeInsets.only(left: Platform.isMacOS ? 78 : 16, right: 16),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(
          bottom: BorderSide(
            color: AppColors.border(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: 'common.back'.tr(),
          ),
          const SizedBox(width: 8),

          // Breadcrumb: Editor > filename
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'converter.editor.title'.tr(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: cs.onSurface,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: cs.outlineVariant,
            ),
          ),
          Expanded(
            child: Text(
              filename,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // File info badges
          if (_mediaInfo != null) ...[
            _headerBadge(_mediaInfo!.qualityLabel),
            const SizedBox(width: 6),
            _headerBadge(_mediaInfo!.durationLabel),
            const SizedBox(width: 6),
            _headerBadge(_mediaInfo!.fileSizeLabel),
          ],
        ],
      ),
    );
  }

  Widget _headerBadge(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBackground =
        isDark
            ? AppColors.darkMuted.withValues(alpha: 0.3)
            : AppColors.surface3(context);
    final badgeTextColor =
        isDark
            ? AppColors.darkLightText
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: badgeTextColor,
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedText =
        isDark ? AppColors.homeDarkTextSecondary : cs.onSurfaceVariant;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(
          top: BorderSide(
            color: AppColors.border(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          // Output directory
          Icon(
            _outputDir != null ? Icons.folder_rounded : Icons.folder_outlined,
            size: 16,
            color: _outputDir != null ? AppColors.accentHighlight : mutedText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _outputDir ?? 'converter.outputSameAsInput'.tr(),
              style: TextStyle(fontSize: 11, color: mutedText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _pickOutputDir,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentHighlight,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _outputDir != null
                  ? 'converter.changeOutput'.tr()
                  : 'converter.chooseOutput'.tr(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          if (_outputDir != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => setState(() => _outputDir = null),
              icon: Icon(Icons.close_rounded, size: 14),
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: mutedText,
              tooltip: 'converter.resetOutput'.tr(),
            ),
          ],
          const SizedBox(width: 16),

          // Export button
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed:
                  (ref
                              .watch(binaryAvailableProvider(BinaryType.ffmpeg))
                              .valueOrNull ??
                          false)
                      ? _export
                      : null,
              icon: const Icon(Icons.bolt_rounded, size: 16),
              label: Text(
                'converter.convert'.tr(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentHighlight,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOutputDir() async {
    final downloadDir = ref.read(downloadPathProvider);
    final dir = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _outputDir ?? downloadDir,
    );
    if (!mounted) return;
    if (dir != null) setState(() => _outputDir = dir);
  }

  Future<void> _export() async {
    final config = ref.read(conversionConfigProvider);
    final queue = ref.read(conversionQueueProvider.notifier);

    try {
      await queue.addToQueue(
        inputPath: widget.filePath,
        config: config,
        mediaInfo: _mediaInfo,
        presetName: 'Editor',
        outputDir: _outputDir,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('converter.startConversion'.tr())),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'converter.conversionError'.tr()}: $e')),
        );
      }
    }
  }
}
