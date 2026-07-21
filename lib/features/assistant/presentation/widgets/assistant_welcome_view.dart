import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import 'quick_action_chips.dart';

class AssistantWelcomeView extends StatefulWidget {
  final void Function(String message) onSendMessage;

  const AssistantWelcomeView({super.key, required this.onSendMessage});

  @override
  State<AssistantWelcomeView> createState() => _AssistantWelcomeViewState();
}

class _AssistantWelcomeViewState extends State<AssistantWelcomeView> {
  final _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _controller.clear();
    widget.onSendMessage(text);
  }

  void _submitFromChip(String message) {
    if (_isSending) return;
    setState(() => _isSending = true);
    _controller.clear();
    widget.onSendMessage(message);
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppLocalizations.assistantGreetingMorning;
    if (hour < 18) return AppLocalizations.assistantGreetingAfternoon;
    return AppLocalizations.assistantGreetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textPrimary = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AssistantMark(),

              const SizedBox(height: AppSpacing.lg),

              Text(
                _getGreeting(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.assistantGreetingQuestion,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              _buildInputBar(theme),

              const SizedBox(height: AppSpacing.xl),

              QuickActionChips(onAction: _submitFromChip),

              const SizedBox(height: AppSpacing.xl),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.smMd,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.border(context).withValues(alpha: 0.72),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 16,
                      color: AppColors.metaText(context),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        AppLocalizations.assistantContextTip,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.metaText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final borderColor = AppColors.border(context);
    final fillColor = AppColors.surface2(context);

    return TextField(
      controller: _controller,
      enabled: !_isSending,
      decoration: InputDecoration(
        hintText: AppLocalizations.assistantInputHint,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.metaText(context),
        ),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: BorderSide(color: AppColors.accentHighlight, width: 1.5),
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.mdLg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child:
              _isSending
                  ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.smMd),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentHighlight,
                      ),
                    ),
                  )
                  : IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: _submit,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.accentHighlight,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(38, 38),
                      maximumSize: const Size(38, 38),
                    ),
                  ),
        ),
      ),
      maxLines: 3,
      minLines: 1,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _submit(),
    );
  }
}

class _AssistantMark extends StatelessWidget {
  const _AssistantMark();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.accentHighlight.withValues(
          alpha: isDark ? 0.16 : 0.12,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(
            alpha: isDark ? 0.42 : 0.32,
          ),
        ),
      ),
      child: Icon(
        Icons.auto_awesome,
        color: AppColors.accentHighlight,
        size: 24,
      ),
    );
  }
}
