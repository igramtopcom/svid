import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';

/// Reusable confirmation dialog.
///
/// Usage:
/// ```dart
/// final confirmed = await AppConfirmDialog.show(
///   context,
///   title: 'Delete Download',
///   message: 'Are you sure you want to delete this?',
///   confirmLabel: 'Delete',
///   isDestructive: true,
/// );
/// if (confirmed) { ... }
/// ```
class AppConfirmDialog {
  AppConfirmDialog._();

  /// Show a confirmation dialog. Returns `true` if confirmed, `false` otherwise.
  /// Supports Enter to confirm (unless destructive) and Esc to cancel.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => _ConfirmDialogBody(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            isDestructive: isDestructive,
          ),
    );
    return result ?? false;
  }
}

class _ConfirmDialogBody extends StatefulWidget {
  const _ConfirmDialogBody({
    required this.title,
    required this.message,
    required this.isDestructive,
    this.confirmLabel,
    this.cancelLabel,
  });

  final String title;
  final String message;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool isDestructive;

  @override
  State<_ConfirmDialogBody> createState() => _ConfirmDialogBodyState();
}

class _ConfirmDialogBodyState extends State<_ConfirmDialogBody> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !widget.isDestructive) {
          Navigator.pop(context, true);
        }
      },
      child: AlertDialog(
        title: Text(widget.title),
        content: Text(widget.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.cancelLabel ?? AppLocalizations.commonCancel),
          ),
          if (widget.isDestructive)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: Text(
                widget.confirmLabel ?? AppLocalizations.commonConfirm,
              ),
            )
          else
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                widget.confirmLabel ?? AppLocalizations.commonConfirm,
              ),
            ),
        ],
      ),
    );
  }
}
