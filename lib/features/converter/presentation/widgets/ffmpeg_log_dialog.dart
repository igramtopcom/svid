import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/core.dart';

/// Modal dialog showing the captured ffmpeg stderr log for a single job.
///
/// Used by the "View Log" action on [ConversionJobCard]. Renders a scrollable
/// monospace text view with a Copy-to-clipboard button. The log is read once
/// when the dialog opens — no live streaming — so reopening shows newer lines
/// for an in-progress job.
class FfmpegLogDialog extends StatelessWidget {
  final String filename;
  final String? log;

  const FfmpegLogDialog({super.key, required this.filename, required this.log});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEmpty = log == null || log!.trim().isEmpty;

    return Dialog(
      backgroundColor: AppColors.surface1(context),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: AppColors.border(context).withValues(alpha: 0.55),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 18,
                    color: AppColors.accentHighlight,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'converter.ffmpegLog.title'.tr(),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          filename,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'converter.ffmpegLog.close'.tr(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border(context)),

            // Log body — monospace, scrollable, selectable
            Flexible(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.border(context).withValues(alpha: 0.55),
                  ),
                ),
                child:
                    isEmpty
                        ? Center(
                          child: Text(
                            'converter.ffmpegLog.empty'.tr(),
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                        : Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(right: 8),
                            child: SelectableText(
                              log!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.45,
                                color: cs.onSurface.withValues(alpha: 0.88),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
              ),
            ),

            // Footer actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text('converter.ffmpegLog.copy'.tr()),
                      onPressed: () async {
                        await ClipboardService.setText(log!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('converter.ffmpegLog.copied'.tr()),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('converter.ffmpegLog.close'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
