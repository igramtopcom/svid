import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/l10n/app_localizations.dart';

/// File concatenation panel — list files, reorder, add/remove.
class ConcatPanel extends StatefulWidget {
  final List<String> initialFiles;
  final ValueChanged<List<String>> onFilesChanged;

  const ConcatPanel({
    super.key,
    this.initialFiles = const [],
    required this.onFilesChanged,
  });

  @override
  State<ConcatPanel> createState() => _ConcatPanelState();
}

class _ConcatPanelState extends State<ConcatPanel> {
  late List<String> _files;

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.initialFiles);
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
          Row(
            children: [
              Text(
                'converter.enhance.mergeFiles'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_files.isNotEmpty)
                Text(
                  '${_files.length} ${'converter.enhance.files'.tr()}',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // File list
          if (_files.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Text(
                'converter.enhance.addFilesToMerge'.tr(),
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _files.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final filePath = _files[index];
                final fileName = p.basename(filePath);
                final ext = p
                    .extension(filePath)
                    .toUpperCase()
                    .replaceAll('.', '');

                return Container(
                  key: ValueKey(filePath),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Drag handle
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      // Index
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: tt.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // File name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fileName,
                              style: tt.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              ext,
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Remove button
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: cs.error.withValues(alpha: 0.7),
                        ),
                        onPressed: () => _removeFile(index),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 8),

          // Add files button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addFiles,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('converter.enhance.addFiles'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex--;
      final item = _files.removeAt(oldIndex);
      _files.insert(newIndex, item);
    });
    widget.onFilesChanged(_files);
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
    widget.onFilesChanged(_files);
  }

  Future<void> _addFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedExtensions,
        allowMultiple: true,
        dialogTitle: 'Select files to merge',
      );
      if (!mounted) return;

      if (result != null && result.files.isNotEmpty) {
        final paths =
            result.files
                .where((f) => f.path != null && File(f.path!).existsSync())
                .map((f) => f.path!)
                .toList();

        if (paths.isNotEmpty) {
          setState(() => _files.addAll(paths));
          widget.onFilesChanged(_files);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.converterOpenPickerFailed),
          ),
        );
      }
    }
  }

  static const _supportedExtensions = [
    'mp4',
    'mkv',
    'webm',
    'avi',
    'mov',
    'ts',
    'flv',
    'wmv',
    'mp3',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
    'm4a',
  ];
}
