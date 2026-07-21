import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/core.dart';
import '../../domain/services/batch_import_service.dart';

/// Show batch download dialog for entering multiple URLs.
/// Returns the list of valid URLs, or null if cancelled.
Future<List<String>?> showBatchUrlImportDialog(BuildContext context) {
  final textController = TextEditingController();
  const batchImportService = BatchImportService();
  BatchImportResult? parseResult;

  return showDialog<List<String>>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setDialogState) => CallbackShortcuts(
                bindings: {
                  SingleActivator(
                    LogicalKeyboardKey.enter,
                    meta: Platform.isMacOS,
                    control: !Platform.isMacOS,
                  ): () {
                    if (parseResult != null && parseResult!.hasValidUrls) {
                      Navigator.pop(context, parseResult!.validUrls);
                    }
                  },
                },
                child: AlertDialog(
                  backgroundColor: AppColors.surface1(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.dialog),
                    side: BorderSide(color: AppColors.border(context)),
                  ),
                  title: Text(AppLocalizations.homeBatchDownloadTitle),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.homeBatchDownloadInputLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: textController,
                          maxLines: 10,
                          decoration: InputDecoration(
                            hintText:
                                AppLocalizations.homeBatchDownloadEmptyHint,
                            filled: true,
                            fillColor: AppColors.surface2(context),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.border(context),
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.border(context),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.accentHighlight,
                                width: 1.5,
                              ),
                            ),
                          ),
                          autofocus: true,
                          onChanged: (text) {
                            setDialogState(() {
                              parseResult =
                                  text.trim().isEmpty
                                      ? null
                                      : batchImportService.parseUrls(text);
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        // Live validation preview
                        if (parseResult != null) ...[
                          Text(
                            AppLocalizations.homeBatchDownloadValidCount(
                              parseResult!.validUrls.length,
                              parseResult!.skippedLines.length,
                            ),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  parseResult!.hasValidUrls
                                      ? AppColors.successGreen
                                      : Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (parseResult!.duplicateCount > 0)
                            Text(
                              AppLocalizations.homeBatchDownloadDuplicatesRemoved(
                                parseResult!.duplicateCount,
                              ),
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ] else
                          Text(
                            'Supports: YouTube, TikTok, Instagram, Twitter, and 1000+ sites',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.commonCancel),
                    ),
                    FilledButton.icon(
                      onPressed:
                          parseResult != null && parseResult!.hasValidUrls
                              ? () {
                                final urls = parseResult!.validUrls;
                                Navigator.pop(context, urls);
                              }
                              : null,
                      icon: const Icon(Icons.download),
                      label: Text(
                        parseResult != null && parseResult!.hasValidUrls
                            ? AppLocalizations.homeBatchDownloadDownloadCount(
                              parseResult!.validUrls.length,
                            )
                            : AppLocalizations.homeBatchDownloadDownloadAll,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ),
  );
}
