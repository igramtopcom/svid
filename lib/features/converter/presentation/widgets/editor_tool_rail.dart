import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/core.dart';

/// Tools available in the standalone editor.
enum EditorTool { trim, crop, color, text, watermark, subtitles, audio, concat }

/// Vertical icon strip on the left side of the standalone editor.
///
/// Each icon selects the corresponding tool panel on the right.
class EditorToolRail extends StatelessWidget {
  final EditorTool activeTool;
  final ValueChanged<EditorTool> onToolSelected;

  const EditorToolRail({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(
          right: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : AppColors.border(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ...EditorTool.values.map(
            (tool) => _ToolRailItem(
              tool: tool,
              isActive: tool == activeTool,
              onTap: () => onToolSelected(tool),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ToolRailItem extends StatefulWidget {
  final EditorTool tool;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolRailItem({
    required this.tool,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ToolRailItem> createState() => _ToolRailItemState();
}

class _ToolRailItemState extends State<_ToolRailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactive =
        isDark
            ? AppColors.homeDarkTextSecondary
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final color =
        widget.isActive
            ? AppColors.accentHighlight
            : (_hover ? Theme.of(context).colorScheme.onSurface : inactive);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 56,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
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
              Icon(_iconFor(widget.tool), size: 20, color: color),
              const SizedBox(height: 3),
              Text(
                _labelFor(widget.tool),
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
