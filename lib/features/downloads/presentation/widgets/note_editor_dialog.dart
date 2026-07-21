import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';

/// Dialog for editing a personal note on a download item.
/// Returns `String?`: null = cancelled, empty string = cleared, non-empty = saved.
class NoteEditorDialog extends StatefulWidget {
  final String initialNote;

  const NoteEditorDialog({super.key, this.initialNote = ''});

  /// Show the dialog and return the result.
  static Future<String?> show(BuildContext context, {String initialNote = ''}) {
    return showDialog<String>(
      context: context,
      builder: (_) => NoteEditorDialog(initialNote: initialNote),
    );
  }

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final TextEditingController _controller;
  static const _maxLength = 200;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
              LogicalKeyboardKey.enter,
              meta: Platform.isMacOS,
              control: !Platform.isMacOS,
            ):
            () => Navigator.pop(context, _controller.text),
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        backgroundColor:
            isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: AppColors.border(context)),
        ),
        title: Text(AppLocalizations.notesEditNote),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.sizeOf(context).height * 0.54,
          ),
          child: TextField(
            controller: _controller,
            maxLength: _maxLength,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: AppLocalizations.notesNoteHint,
              filled: true,
              fillColor: AppColors.surface2(context),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(color: AppColors.border(context)),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(color: AppColors.border(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(
                  color: AppColors.accentHighlight,
                  width: 1.5,
                ),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: AppLocalizations.notesClearNote,
                onPressed: () => _controller.clear(),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(AppLocalizations.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(AppLocalizations.commonSave),
          ),
        ],
      ),
    );
  }
}
