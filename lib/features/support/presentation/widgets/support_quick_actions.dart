import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../screens/feature_requests_screen.dart';
import 'bug_report_dialog.dart';
import 'create_ticket_dialog.dart';

/// Three primary support actions in the V2 utility surface.
class SupportQuickActions extends StatelessWidget {
  final VoidCallback onTicketCreated;

  const SupportQuickActions({super.key, required this.onTicketCreated});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 640;
        final cards = [
          _ConciergeCard(
            icon: Icons.mail_outlined,
            title: AppLocalizations.supportNewTicket,
            description:
                'Direct line to our technical support engineers for complex inquiries.',
            isPrimary: true,
            onTap:
                () => showDialog(
                  context: context,
                  builder:
                      (_) => CreateTicketDialog(onCreated: onTicketCreated),
                ),
          ),
          _ConciergeCard(
            icon: Icons.bug_report_outlined,
            title: AppLocalizations.settingsAccountReportBug,
            description:
                'Help us improve ${BrandConfig.current.appName} by documenting technical inconsistencies.',
            isPrimary: false,
            onTap:
                () => showDialog(
                  context: context,
                  builder: (_) => const BugReportDialog(),
                ),
          ),
          _ConciergeCard(
            icon: Icons.lightbulb_outline,
            title: AppLocalizations.supportFeatureRequests,
            description:
                'Shape the future of cinematic video processing with your ideas.',
            isPrimary: false,
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FeatureRequestsScreen(),
                  ),
                ),
          ),
        ];

        if (!isWide) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: AppSpacing.lg),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConciergeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ConciergeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_ConciergeCard> createState() => _ConciergeCardState();
}

class _ConciergeCardState extends State<_ConciergeCard> {
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color:
                isDark
                    ? (_hovered
                        ? AppColors.homeDarkCardHover
                        : AppColors.homeDarkCardBg)
                    : (_hovered
                        ? AppColors.surface2(context)
                        : AppColors.surface1(context)),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? (_hovered
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.homeDarkBorderSubtle)
                      : (_hovered
                          ? AppColors.accentHighlight.withValues(alpha: 0.32)
                          : AppColors.border(context)),
            ),
            boxShadow:
                isDark
                    ? null
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hovered ? 0.07 : 0.035,
                        ),
                        blurRadius: _hovered ? 14 : 8,
                        offset: Offset(0, _hovered ? 5 : 2),
                      ),
                    ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.accentHighlight.withValues(alpha: 0.22),
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: 28,
                  color: AppColors.accentHighlight,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // CTA button
              SizedBox(
                width: double.infinity,
                child:
                    widget.isPrimary
                        ? FilledButton(
                          onPressed: widget.onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentHighlight,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            textStyle: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                          child: Text(widget.title),
                        )
                        : OutlinedButton(
                          onPressed: widget.onTap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accentHighlight,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            side: BorderSide(color: AppColors.brand),
                            textStyle: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                          child: Text(widget.title),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
