import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/skeleton_list.dart';
import '../providers/feedback_providers.dart';
import '../widgets/feature_request_skeleton.dart';

class FeatureRequestsScreen extends ConsumerWidget {
  const FeatureRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(featureRequestsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return Scaffold(
      backgroundColor: pageBg,
      body: Column(
        children: [
          Container(
            height: 56,
            padding: EdgeInsets.only(
              left: Platform.isMacOS ? 78 : 8,
              right: 16,
            ),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context),
              border: Border(
                bottom: BorderSide(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.border(context),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppLocalizations.featureRequestsTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showSubmitDialog(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    AppLocalizations.featureRequestsSubmit,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.smMd,
                    ),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ColoredBox(
              color: pageBg,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: requestsAsync.when(
                    data: (requests) {
                      if (requests.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 48,
                                color: theme.colorScheme.outline.withValues(
                                  alpha: AppOpacity.scrim,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                AppLocalizations.featureRequestsEmpty,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          // Stable per-request key — vote actions mutate list order.
                          return Padding(
                            key: ValueKey<String>(
                              'feature_request_${request.id}',
                            ),
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _FeatureRequestCard(
                              title: request.title,
                              description: request.description,
                              status: request.status,
                              upvotes: request.upvotes,
                              adminNotes: request.adminNotes,
                              onVote: () => _vote(ref, request.id),
                            ),
                          );
                        },
                      );
                    },
                    loading:
                        () => SkeletonList(
                          itemCount: 8,
                          padding: const EdgeInsets.all(AppSpacing.mdLg),
                          itemBuilder:
                              (_, __) => const FeatureRequestSkeleton(),
                        ),
                    error:
                        (error, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 40,
                                color: theme.colorScheme.error.withValues(
                                  alpha: AppOpacity.secondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.smMd),
                              Text(
                                AppLocalizations.supportLoadError,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton.icon(
                                onPressed:
                                    () =>
                                        ref.invalidate(featureRequestsProvider),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(AppLocalizations.commonRetry),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _vote(WidgetRef ref, String featureId) async {
    final service = ref.read(backendServiceProvider);
    final result = await service.voteFeature(featureId);
    result.when(
      success: (_) => ref.invalidate(featureRequestsProvider),
      failure: (e) => appLogger.warning('Failed to vote on feature: $e'),
    );
  }

  void _showSubmitDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.dialog),
            side: BorderSide(color: AppColors.border(ctx)),
          ),
          backgroundColor: AppColors.surface1(ctx),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            0,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(
                    alpha: AppOpacity.pressed,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.24),
                  ),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  size: 22,
                  color: AppColors.successGreen,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.featureRequestsSubmit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Share improvements for future releases',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: AppOpacity.secondary,
                        ),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.featureRequestsTitleField,
                      filled: true,
                      fillColor: AppColors.surface2(ctx),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(color: AppColors.border(ctx)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(color: AppColors.border(ctx)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(
                          color: AppColors.accentHighlight,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: const BorderSide(color: AppColors.errorRed),
                      ),
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    validator:
                        (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: descriptionController,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.featureRequestsDescriptionField,
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: AppColors.surface2(ctx),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(color: AppColors.border(ctx)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(color: AppColors.border(ctx)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(
                          color: AppColors.accentHighlight,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: const BorderSide(color: AppColors.errorRed),
                      ),
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    maxLines: 4,
                    minLines: 2,
                    validator:
                        (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdLg,
                  vertical: AppSpacing.smMd,
                ),
              ),
              child: Text(AppLocalizations.commonCancel),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final service = ref.read(backendServiceProvider);
                final result = await service.submitFeatureRequest(
                  title: titleController.text.trim(),
                  description: descriptionController.text.trim(),
                );
                result.when(
                  success: (_) {
                    ref.invalidate(featureRequestsProvider);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  failure: (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.supportLoadError),
                        ),
                      );
                    }
                  },
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentHighlight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.smMd,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: Text(
                AppLocalizations.supportSubmit,
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureRequestCard extends StatefulWidget {
  final String title;
  final String description;
  final String status;
  final int upvotes;
  final String adminNotes;
  final VoidCallback onVote;

  const _FeatureRequestCard({
    required this.title,
    required this.description,
    required this.status,
    required this.upvotes,
    required this.adminNotes,
    required this.onVote,
  });

  @override
  State<_FeatureRequestCard> createState() => _FeatureRequestCardState();
}

class _FeatureRequestCardState extends State<_FeatureRequestCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (statusLabel, statusColor) = switch (widget.status) {
      'open' => ('Open', AppColors.accentHighlight),
      'under_review' => ('Under Review', AppColors.warningAmber),
      'planned' => ('Planned', AppColors.infoBlue),
      'in_progress' => ('In Progress', AppColors.statusInProgress),
      'completed' => ('Completed', AppColors.successGreen),
      'declined' => ('Declined', AppColors.statusQueued),
      _ => (widget.status.replaceAll('_', ' '), AppColors.statusQueued),
    };

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color:
              _hovered
                  ? (isDark
                      ? AppColors.homeDarkCardHover
                      : AppColors.surface2(context))
                  : (isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context)),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                isDark
                    ? (_hovered
                        ? AppColors.homeDarkBorderStrong
                        : AppColors.homeDarkBorderSubtle)
                    : AppColors.border(context),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.mdLg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vote button
            _VoteButton(count: widget.upvotes, onTap: widget.onVote),
            const SizedBox(width: AppSpacing.md),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smMd),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(
                            alpha: isDark ? 0.18 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(
                            color: statusColor.withValues(
                              alpha: isDark ? 0.34 : 0.26,
                            ),
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          style: AppTypography.compact.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.adminNotes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.smMd),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.smMd),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(
                          alpha: AppOpacity.hover,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                          color: AppColors.accentHighlight.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            size: 14,
                            color: AppColors.accentHighlight.withValues(
                              alpha: AppOpacity.strong,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              widget.adminNotes,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoteButton extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _VoteButton({required this.count, required this.onTap});

  @override
  State<_VoteButton> createState() => _VoteButtonState();
}

class _VoteButtonState extends State<_VoteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color:
                _hovered
                    ? AppColors.brand.withValues(alpha: AppOpacity.subtle)
                    : (isDark
                        ? AppColors.homeDarkCardHover
                        : AppColors.surface2(context)),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  _hovered
                      ? AppColors.accentHighlight.withValues(alpha: 0.28)
                      : (isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.border(context)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_upward,
                size: 16,
                color:
                    _hovered
                        ? AppColors.accentHighlight
                        : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${widget.count}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      _hovered
                          ? AppColors.accentHighlight
                          : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
