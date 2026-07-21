import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/media_info.dart';

/// Crop configuration widget.
///
/// Provides number inputs for X, Y, width, height and quick aspect ratio
/// presets (16:9, 9:16, 1:1, 4:3, "Remove TikTok watermark").
class CropConfigWidget extends StatefulWidget {
  final MediaInfo? mediaInfo;
  final CropConfig? initialCrop;
  final ValueChanged<CropConfig?> onCropChanged;

  const CropConfigWidget({
    super.key,
    this.mediaInfo,
    this.initialCrop,
    required this.onCropChanged,
  });

  @override
  State<CropConfigWidget> createState() => _CropConfigWidgetState();
}

class _CropConfigWidgetState extends State<CropConfigWidget> {
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _widthCtrl;
  late TextEditingController _heightCtrl;

  int get _videoWidth => widget.mediaInfo?.width ?? 1920;
  int get _videoHeight => widget.mediaInfo?.height ?? 1080;

  @override
  void initState() {
    super.initState();
    _xCtrl = TextEditingController(
        text: '${widget.initialCrop?.x ?? 0}');
    _yCtrl = TextEditingController(
        text: '${widget.initialCrop?.y ?? 0}');
    _widthCtrl = TextEditingController(
        text: '${widget.initialCrop?.width ?? _videoWidth}');
    _heightCtrl = TextEditingController(
        text: '${widget.initialCrop?.height ?? _videoHeight}');
  }

  @override
  void dispose() {
    _xCtrl.dispose();
    _yCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha:0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'converter.enhance.cropRegion'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (widget.mediaInfo != null)
            Text(
              '${'converter.enhance.sourceSize'.tr()}: ${_videoWidth}x$_videoHeight',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha:0.7),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 10),

          // Quick presets
          Text(
            'converter.enhance.quickPresets'.tr(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PresetChip(
                label: '16:9',
                onTap: () => _applyCropRatio(16, 9),
              ),
              _PresetChip(
                label: '9:16',
                onTap: () => _applyCropRatio(9, 16),
              ),
              _PresetChip(
                label: '1:1',
                onTap: () => _applyCropRatio(1, 1),
              ),
              _PresetChip(
                label: '4:3',
                onTap: () => _applyCropRatio(4, 3),
              ),
              _PresetChip(
                label: 'converter.enhance.removeTiktokWm'.tr(),
                onTap: _removeTikTokWatermark,
              ),
              _PresetChip(
                label: 'converter.enhance.resetCrop'.tr(),
                onTap: _resetCrop,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Number inputs: X, Y, Width, Height
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'X',
                  controller: _xCtrl,
                  onChanged: (_) => _emitCrop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Y',
                  controller: _yCtrl,
                  onChanged: (_) => _emitCrop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'converter.enhance.width'.tr(),
                  controller: _widthCtrl,
                  onChanged: (_) => _emitCrop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'converter.enhance.height'.tr(),
                  controller: _heightCtrl,
                  onChanged: (_) => _emitCrop(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Crop preview (aspect ratio indicator)
          _CropPreview(
            videoWidth: _videoWidth,
            videoHeight: _videoHeight,
            cropX: int.tryParse(_xCtrl.text) ?? 0,
            cropY: int.tryParse(_yCtrl.text) ?? 0,
            cropWidth: int.tryParse(_widthCtrl.text) ?? _videoWidth,
            cropHeight: int.tryParse(_heightCtrl.text) ?? _videoHeight,
          ),
        ],
      ),
    );
  }

  void _applyCropRatio(int ratioW, int ratioH) {
    // Calculate largest crop area fitting the given aspect ratio within the video
    int cropWidth;
    int cropHeight;
    if (_videoWidth / _videoHeight > ratioW / ratioH) {
      // Video is wider: constrain by height
      cropHeight = _videoHeight;
      cropWidth = (cropHeight * ratioW / ratioH).round();
      // Ensure width is even (ffmpeg requirement)
      cropWidth = cropWidth ~/ 2 * 2;
    } else {
      // Video is taller: constrain by width
      cropWidth = _videoWidth;
      cropHeight = (cropWidth * ratioH / ratioW).round();
      cropHeight = cropHeight ~/ 2 * 2;
    }

    final x = ((_videoWidth - cropWidth) / 2).round();
    final y = ((_videoHeight - cropHeight) / 2).round();

    setState(() {
      _xCtrl.text = '$x';
      _yCtrl.text = '$y';
      _widthCtrl.text = '$cropWidth';
      _heightCtrl.text = '$cropHeight';
    });
    _emitCrop();
  }

  void _removeTikTokWatermark() {
    // TikTok watermark is typically at the bottom ~50px
    final cropHeight = _videoHeight - 50;
    setState(() {
      _xCtrl.text = '0';
      _yCtrl.text = '0';
      _widthCtrl.text = '$_videoWidth';
      _heightCtrl.text = '${cropHeight ~/ 2 * 2}'; // Ensure even
    });
    _emitCrop();
  }

  void _resetCrop() {
    setState(() {
      _xCtrl.text = '0';
      _yCtrl.text = '0';
      _widthCtrl.text = '$_videoWidth';
      _heightCtrl.text = '$_videoHeight';
    });
    widget.onCropChanged(null);
  }

  void _emitCrop() {
    var x = int.tryParse(_xCtrl.text) ?? 0;
    var y = int.tryParse(_yCtrl.text) ?? 0;
    var w = int.tryParse(_widthCtrl.text) ?? _videoWidth;
    var h = int.tryParse(_heightCtrl.text) ?? _videoHeight;

    // Clamp values to valid range within video dimensions
    x = x.clamp(0, (_videoWidth - 2).clamp(0, _videoWidth));
    y = y.clamp(0, (_videoHeight - 2).clamp(0, _videoHeight));
    w = w.clamp(2, _videoWidth - x);
    h = h.clamp(2, _videoHeight - y);

    // Ensure even dimensions (FFmpeg requirement for most codecs)
    w = w ~/ 2 * 2;
    h = h ~/ 2 * 2;

    if (w > 0 && h > 0) {
      widget.onCropChanged(CropConfig(x: x, y: y, width: w, height: h));
    }
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha:0.5),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onChanged,
            style: tt.bodySmall,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha:0.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple visual preview showing the crop area within the video frame.
class _CropPreview extends StatelessWidget {
  final int videoWidth;
  final int videoHeight;
  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;

  const _CropPreview({
    required this.videoWidth,
    required this.videoHeight,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Render at a max of 200px wide, maintaining aspect ratio
    const maxWidth = 200.0;
    final aspectRatio = videoWidth / videoHeight;
    final previewWidth = maxWidth;
    final previewHeight = maxWidth / aspectRatio;

    final scaleX = previewWidth / videoWidth;
    final scaleY = previewHeight / videoHeight;

    return Center(
      child: SizedBox(
        width: previewWidth,
        height: previewHeight,
        child: Stack(
          children: [
            // Full video area (dimmed)
            Container(
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
            ),
            // Crop area (highlighted)
            Positioned(
              left: cropX * scaleX,
              top: cropY * scaleY,
              width: cropWidth * scaleX,
              height: cropHeight * scaleY,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha:0.2),
                  border: Border.all(
                    color: cs.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
