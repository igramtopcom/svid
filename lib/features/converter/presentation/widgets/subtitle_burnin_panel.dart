import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Panel for selecting a subtitle file to burn into the video.
///
/// Supports .srt, .ass, .ssa, .vtt subtitle formats.
class SubtitleBurninPanel extends StatefulWidget {
  final String? initialPath;
  final ValueChanged<String?> onPathChanged;

  const SubtitleBurninPanel({
    super.key,
    this.initialPath,
    required this.onPathChanged,
  });

  @override
  State<SubtitleBurninPanel> createState() => _SubtitleBurninPanelState();
}

class _SubtitleBurninPanelState extends State<SubtitleBurninPanel> {
  String? _subtitlePath;

  @override
  void initState() {
    super.initState();
    _subtitlePath = widget.initialPath;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'converter.enhance.burnSubtitles'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'converter.enhance.burnSubtitlesHint'.tr(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),

          // File picker
          InkWell(
            onTap: _pickSubtitle,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      _subtitlePath != null
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _subtitlePath != null
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    size: 20,
                    color:
                        _subtitlePath != null
                            ? cs.primary
                            : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _subtitlePath != null
                          ? p.basename(_subtitlePath!)
                          : 'converter.enhance.selectSubtitle'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color:
                            _subtitlePath != null
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_subtitlePath != null)
                    InkWell(
                      onTap: () {
                        setState(() => _subtitlePath = null);
                        widget.onPathChanged(null);
                      },
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (_subtitlePath != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'converter.enhance.burnSubtitlesInfo'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickSubtitle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub'],
      allowMultiple: false,
    );
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      setState(() => _subtitlePath = result.files.single.path);
      widget.onPathChanged(_subtitlePath);
    }
  }
}
