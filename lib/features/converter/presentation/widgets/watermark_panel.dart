import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/output_format.dart';

/// Panel for configuring watermark overlay: image picker + position selector.
class WatermarkPanel extends StatefulWidget {
  final String? initialPath;
  final WatermarkPosition? initialPosition;
  final void Function({String? path, WatermarkPosition? position}) onChanged;

  const WatermarkPanel({
    super.key,
    this.initialPath,
    this.initialPosition,
    required this.onChanged,
  });

  @override
  State<WatermarkPanel> createState() => _WatermarkPanelState();
}

class _WatermarkPanelState extends State<WatermarkPanel> {
  String? _imagePath;
  WatermarkPosition _position = WatermarkPosition.bottomRight;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.initialPath;
    _position = widget.initialPosition ?? WatermarkPosition.bottomRight;
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
            'converter.enhance.watermark'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // Image picker
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      _imagePath != null
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _imagePath != null
                        ? Icons.image_rounded
                        : Icons.add_photo_alternate_rounded,
                    size: 20,
                    color:
                        _imagePath != null ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _imagePath != null
                          ? p.basename(_imagePath!)
                          : 'converter.enhance.selectImage'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color:
                            _imagePath != null
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_imagePath != null)
                    InkWell(
                      onTap: () {
                        setState(() => _imagePath = null);
                        _emit();
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

          const SizedBox(height: 12),

          // Position selector
          Text(
            'converter.enhance.position'.tr(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),

          // 3x3 position grid (5 positions)
          SizedBox(
            height: 80,
            width: 130,
            child: Stack(
              children: [
                // Background grid
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                // Position buttons
                Positioned(
                  top: 4,
                  left: 4,
                  child: _PositionDot(
                    isSelected: _position == WatermarkPosition.topLeft,
                    onTap: () => _setPosition(WatermarkPosition.topLeft),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _PositionDot(
                    isSelected: _position == WatermarkPosition.topRight,
                    onTap: () => _setPosition(WatermarkPosition.topRight),
                  ),
                ),
                Center(
                  child: _PositionDot(
                    isSelected: _position == WatermarkPosition.center,
                    onTap: () => _setPosition(WatermarkPosition.center),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: _PositionDot(
                    isSelected: _position == WatermarkPosition.bottomLeft,
                    onTap: () => _setPosition(WatermarkPosition.bottomLeft),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: _PositionDot(
                    isSelected: _position == WatermarkPosition.bottomRight,
                    onTap: () => _setPosition(WatermarkPosition.bottomRight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      setState(() => _imagePath = result.files.single.path);
      _emit();
    }
  }

  void _setPosition(WatermarkPosition pos) {
    setState(() => _position = pos);
    _emit();
  }

  void _emit() {
    widget.onChanged(
      path: _imagePath,
      position: _imagePath != null ? _position : null,
    );
  }
}

class _PositionDot extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _PositionDot({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child:
            isSelected
                ? Icon(Icons.check_rounded, size: 12, color: cs.onPrimary)
                : null,
      ),
    );
  }
}
