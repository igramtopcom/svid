import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../converter/presentation/providers/converter_providers.dart';
import '../../../converter/presentation/providers/conversion_queue_provider.dart';
import '../../../converter/presentation/widgets/brightness_contrast_panel.dart';
import '../../../converter/presentation/widgets/crop_config_widget.dart';
import '../../../converter/presentation/widgets/trim_panel.dart';
import '../../../converter/presentation/widgets/volume_panel.dart';
import '../../../downloads/domain/entities/download_entity.dart';

/// Edit mode tools available in the player overlay.
enum PlayerEditTool { trim, crop, adjust, volume }

/// Edit overlay that slides in from the right side of the video player.
///
/// Provides quick-edit tools (trim, crop, adjust, volume) directly in the
/// player context — zero navigation away from the video. The user picks a
/// tool from the bottom toolbar, configures it in the side panel, then
/// hits Export to create a conversion job.
class PlayerEditOverlay extends ConsumerStatefulWidget {
  final Player player;
  final DownloadEntity download;
  final VoidCallback onClose;

  const PlayerEditOverlay({
    super.key,
    required this.player,
    required this.download,
    required this.onClose,
  });

  @override
  ConsumerState<PlayerEditOverlay> createState() => _PlayerEditOverlayState();
}

class _PlayerEditOverlayState extends ConsumerState<PlayerEditOverlay>
    with SingleTickerProviderStateMixin {
  PlayerEditTool _activeTool = PlayerEditTool.trim;
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 820;
        final panelWidth =
            isCompact
                ? constraints.maxWidth
                : (constraints.maxWidth * 0.42).clamp(360.0, 520.0);

        return Row(
          children: [
            if (!isCompact) const Expanded(child: SizedBox.shrink()),

            // Edit panel — slides in from right, but keeps a usable width on
            // compact windows instead of squeezing controls into a thin rail.
            SizedBox(
              width: panelWidth,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.92),
                    border: Border(
                      left: BorderSide(
                        color: AppColors.accentHighlight.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(cs),

                      // Tool content area
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _buildToolContent(),
                        ),
                      ),

                      // Bottom toolbar + export
                      _buildToolbar(cs),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.darkMuted.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.accentHighlight,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'player.editMode'.tr(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: AppColors.darkLightText,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.darkMetaText,
            ),
            tooltip: 'common.close'.tr(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolContent() {
    switch (_activeTool) {
      case PlayerEditTool.trim:
        return _buildTrimTool();
      case PlayerEditTool.crop:
        return _buildCropTool();
      case PlayerEditTool.adjust:
        return _buildAdjustTool();
      case PlayerEditTool.volume:
        return _buildVolumeTool();
    }
  }

  Widget _buildTrimTool() {
    // Get media duration from download entity
    final duration =
        widget.download.duration != null
            ? Duration(seconds: widget.download.duration!)
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolSectionTitle('TRIM / CUT'),
        const SizedBox(height: 8),
        TrimPanel(
          mediaDuration: duration,
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
        ),
      ],
    );
  }

  Widget _buildCropTool() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolSectionTitle('player.crop'.tr()),
        const SizedBox(height: 8),
        CropConfigWidget(
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
        ),
      ],
    );
  }

  Widget _buildAdjustTool() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolSectionTitle('player.adjustments'.tr()),
        const SizedBox(height: 8),
        BrightnessContrastPanel(
          initialBrightness: ref.read(conversionConfigProvider).brightness,
          initialContrast: ref.read(conversionConfigProvider).contrast,
          initialSaturation: ref.read(conversionConfigProvider).saturation,
          initialGamma: ref.read(conversionConfigProvider).gamma,
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
      ],
    );
  }

  Widget _buildVolumeTool() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolSectionTitle('player.volume'.tr()),
        const SizedBox(height: 8),
        VolumePanel(
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
        ),
      ],
    );
  }

  Widget _toolSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: AppColors.darkMetaText,
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.darkMuted.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Tool selection — flexible layout
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 4,
            runSpacing: 4,
            children:
                PlayerEditTool.values.map((tool) {
                  final isActive = tool == _activeTool;
                  return _ToolButton(
                    icon: _toolIcon(tool),
                    label: _toolLabel(tool),
                    isActive: isActive,
                    onTap: () => setState(() => _activeTool = tool),
                  );
                }).toList(),
          ),
          const SizedBox(height: 8),

          // Export button
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton.icon(
              onPressed:
                  (ref
                              .watch(binaryAvailableProvider(BinaryType.ffmpeg))
                              .valueOrNull ??
                          false)
                      ? _exportEdit
                      : null,
              icon: const Icon(Icons.bolt_rounded, size: 14),
              label: Text(
                'converter.convert'.tr(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentHighlight,
                foregroundColor: Colors.white,
                elevation: 0,
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

  IconData _toolIcon(PlayerEditTool tool) {
    switch (tool) {
      case PlayerEditTool.trim:
        return Icons.content_cut_rounded;
      case PlayerEditTool.crop:
        return Icons.crop_rounded;
      case PlayerEditTool.adjust:
        return Icons.tune_rounded;
      case PlayerEditTool.volume:
        return Icons.volume_up_rounded;
    }
  }

  String _toolLabel(PlayerEditTool tool) {
    switch (tool) {
      case PlayerEditTool.trim:
        return 'Trim';
      case PlayerEditTool.crop:
        return 'Crop';
      case PlayerEditTool.adjust:
        return 'Adjust';
      case PlayerEditTool.volume:
        return 'Volume';
    }
  }

  Future<void> _exportEdit() async {
    final download = widget.download;
    final filePath = download.savePath;
    final config = ref.read(conversionConfigProvider);
    final queue = ref.read(conversionQueueProvider.notifier);

    try {
      await queue.addToQueue(
        inputPath: filePath,
        config: config,
        presetName: 'Quick Edit',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('converter.startConversion'.tr())),
        );
        widget.onClose();
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

/// Small tool button for the edit toolbar.
class _ToolButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isActive
            ? AppColors.accentHighlight
            : (_hover ? AppColors.darkLightText : AppColors.darkMetaText);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                widget.isActive
                    ? AppColors.accentHighlight.withValues(alpha: 0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                widget.isActive
                    ? Border.all(
                      color: AppColors.accentHighlight.withValues(alpha: 0.4),
                    )
                    : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
}
