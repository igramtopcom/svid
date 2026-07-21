import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/media_info.dart';
import '../providers/converter_providers.dart';
import '../widgets/brightness_contrast_panel.dart';
import '../widgets/color_grading_widget.dart';
import '../widgets/concat_panel.dart';
import '../widgets/crop_config_widget.dart';
import '../widgets/subtitle_burnin_panel.dart';
import '../widgets/text_overlay_widget.dart';
import '../widgets/trim_panel.dart';
import '../widgets/volume_panel.dart';
import '../widgets/watermark_panel.dart';

/// Tools available in the standalone editor.
enum EditorTool { trim, crop, color, text, watermark, subtitles, audio, concat }

/// Right properties panel for the standalone editor — two-panel tabbed layout.
///
/// Contains a horizontal tab bar (8 tools) at the top, with the active tool's
/// configuration widget below. All changes are written to
/// [conversionConfigProvider] so the export button can read the final config.
class EditorPropertiesPanel extends ConsumerStatefulWidget {
  final MediaInfo? mediaInfo;

  const EditorPropertiesPanel({super.key, this.mediaInfo});

  @override
  ConsumerState<EditorPropertiesPanel> createState() =>
      _EditorPropertiesPanelState();
}

class _EditorPropertiesPanelState extends ConsumerState<EditorPropertiesPanel> {
  EditorTool _activeTool = EditorTool.trim;

  // Local state for concat files and color effect (not in conversionConfig)
  List<String> _concatFiles = [];
  String? _selectedColorEffectId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(
          left: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : AppColors.border(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        children: [
          // Horizontal tool tab bar
          _buildTabBar(),

          // Section header for active tool
          _buildToolHeader(),

          // Tool-specific widget
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: _buildToolWidget(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : AppColors.border(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children:
              EditorTool.values.map((tool) {
                final isActive = tool == _activeTool;
                return _EditorTab(
                  tool: tool,
                  isActive: isActive,
                  onTap: () => setState(() => _activeTool = tool),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildToolHeader() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderSubtle
                    : AppColors.border(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _toolTitle(_activeTool),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolWidget() {
    switch (_activeTool) {
      case EditorTool.trim:
        return _buildTrim();
      case EditorTool.crop:
        return _buildCrop();
      case EditorTool.color:
        return _buildColor();
      case EditorTool.text:
        return _buildText();
      case EditorTool.watermark:
        return _buildWatermark();
      case EditorTool.subtitles:
        return _buildSubtitles();
      case EditorTool.audio:
        return _buildAudio();
      case EditorTool.concat:
        return _buildConcat();
    }
  }

  // ══════════════════════════════════════════════════════════
  //  Tool widgets — each reads/writes conversionConfigProvider
  // ══════════════════════════════════════════════════════════

  Widget _buildTrim() {
    return TrimPanel(
      mediaDuration: widget.mediaInfo?.duration,
      initialTrim: ref.read(conversionConfigProvider).trim,
      onTrimChanged: (trim) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(trim: trim, clearTrim: trim == null),
            );
      },
    );
  }

  Widget _buildCrop() {
    return CropConfigWidget(
      mediaInfo: widget.mediaInfo,
      initialCrop: ref.read(conversionConfigProvider).crop,
      onCropChanged: (crop) {
        final notifier = ref.read(conversionConfigProvider.notifier);
        if (crop != null) {
          notifier.setConfig(
            ref.read(conversionConfigProvider).copyWith(crop: crop),
          );
        } else {
          notifier.setConfig(
            ref.read(conversionConfigProvider).copyWith(clearCrop: true),
          );
        }
      },
    );
  }

  Widget _buildColor() {
    final config = ref.read(conversionConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brightness / contrast / saturation / gamma
        BrightnessContrastPanel(
          initialBrightness: config.brightness,
          initialContrast: config.contrast,
          initialSaturation: config.saturation,
          initialGamma: config.gamma,
          onChanged: ({
            double? brightness,
            double? contrast,
            double? saturation,
            double? gamma,
          }) {
            ref
                .read(conversionConfigProvider.notifier)
                .setConfig(
                  ref
                      .read(conversionConfigProvider)
                      .copyWith(
                        brightness: brightness,
                        contrast: contrast,
                        saturation: saturation,
                        gamma: gamma,
                        clearBrightness: brightness == null,
                        clearContrast: contrast == null,
                        clearSaturation: saturation == null,
                        clearGamma: gamma == null,
                      ),
                );
          },
        ),
        const SizedBox(height: 16),

        // Color grading presets
        Text(
          'converter.enhance.colorGrading'.tr(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ColorGradingWidget(
          selectedEffectId: _selectedColorEffectId,
          onPresetSelected: (preset) {
            setState(() => _selectedColorEffectId = preset?.id);
            final notifier = ref.read(conversionConfigProvider.notifier);
            if (preset != null) {
              notifier.setConfig(
                ref
                    .read(conversionConfigProvider)
                    .copyWith(colorEffect: preset.filterChain),
              );
            } else {
              notifier.setConfig(
                ref
                    .read(conversionConfigProvider)
                    .copyWith(clearColorEffect: true),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildText() {
    final config = ref.read(conversionConfigProvider);
    return TextOverlayWidget(
      initialText: config.textOverlay,
      initialConfig: config.textOverlayConfig,
      onTextChanged: (text) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(textOverlay: text, clearTextOverlay: text == null),
            );
      },
      onConfigChanged: (overlayConfig) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(textOverlayConfig: overlayConfig),
            );
      },
    );
  }

  Widget _buildWatermark() {
    final config = ref.read(conversionConfigProvider);
    return WatermarkPanel(
      initialPath: config.watermarkPath,
      initialPosition: config.watermarkPosition,
      onChanged: ({String? path, position}) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(
                    watermarkPath: path,
                    watermarkPosition: position,
                    clearWatermarkPath: path == null,
                    clearWatermarkPosition: position == null,
                  ),
            );
      },
    );
  }

  Widget _buildSubtitles() {
    return SubtitleBurninPanel(
      initialPath: ref.read(conversionConfigProvider).subtitlePath,
      onPathChanged: (path) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(
                    subtitlePath: path,
                    clearSubtitlePath: path == null,
                  ),
            );
      },
    );
  }

  Widget _buildAudio() {
    return VolumePanel(
      initialVolumeDb: ref.read(conversionConfigProvider).volumeDb,
      onVolumeChanged: (db) {
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref
                  .read(conversionConfigProvider)
                  .copyWith(volumeDb: db, clearVolumeDb: db == null),
            );
      },
    );
  }

  Widget _buildConcat() {
    return ConcatPanel(
      initialFiles: _concatFiles,
      onFilesChanged: (files) {
        setState(() => _concatFiles = files);
        // Store in config for export
        ref
            .read(conversionConfigProvider.notifier)
            .setConfig(
              ref.read(conversionConfigProvider).copyWith(concatFiles: files),
            );
      },
    );
  }

  String _toolTitle(EditorTool tool) {
    switch (tool) {
      case EditorTool.trim:
        return 'converter.editor.trim'.tr();
      case EditorTool.crop:
        return 'converter.editor.crop'.tr();
      case EditorTool.color:
        return 'converter.editor.color'.tr();
      case EditorTool.text:
        return 'converter.editor.text'.tr();
      case EditorTool.watermark:
        return 'converter.editor.watermark'.tr();
      case EditorTool.subtitles:
        return 'converter.editor.subtitles'.tr();
      case EditorTool.audio:
        return 'converter.editor.audio'.tr();
      case EditorTool.concat:
        return 'converter.editor.merge'.tr();
    }
  }
}

/// Horizontal tab item for the editor tool bar.
class _EditorTab extends StatefulWidget {
  final EditorTool tool;
  final bool isActive;
  final VoidCallback onTap;

  const _EditorTab({
    required this.tool,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends State<_EditorTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactive =
        isDark
            ? AppColors.homeDarkTextSecondary
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final color =
        isActive
            ? AppColors.accentHighlight
            : (_hover ? Theme.of(context).colorScheme.onSurface : inactive);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color:
                isActive
                    ? AppColors.accentHighlight.withValues(alpha: 0.10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                isActive
                    ? Border.all(
                      color: AppColors.accentHighlight.withValues(alpha: 0.45),
                    )
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(widget.tool), size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                _labelFor(widget.tool),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(EditorTool tool) {
    switch (tool) {
      case EditorTool.trim:
        return Icons.content_cut_rounded;
      case EditorTool.crop:
        return Icons.crop_rounded;
      case EditorTool.color:
        return Icons.palette_rounded;
      case EditorTool.text:
        return Icons.text_fields_rounded;
      case EditorTool.watermark:
        return Icons.branding_watermark_rounded;
      case EditorTool.subtitles:
        return Icons.subtitles_rounded;
      case EditorTool.audio:
        return Icons.volume_up_rounded;
      case EditorTool.concat:
        return Icons.merge_rounded;
    }
  }

  String _labelFor(EditorTool tool) {
    switch (tool) {
      case EditorTool.trim:
        return 'converter.editor.trim'.tr();
      case EditorTool.crop:
        return 'converter.editor.crop'.tr();
      case EditorTool.color:
        return 'converter.editor.color'.tr();
      case EditorTool.text:
        return 'converter.editor.text'.tr();
      case EditorTool.watermark:
        return 'converter.editor.watermark'.tr();
      case EditorTool.subtitles:
        return 'converter.editor.subtitles'.tr();
      case EditorTool.audio:
        return 'converter.editor.audio'.tr();
      case EditorTool.concat:
        return 'converter.editor.merge'.tr();
    }
  }
}
