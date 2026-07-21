import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../support/presentation/widgets/bug_report_dialog.dart';
import '../../../support/presentation/widgets/create_ticket_dialog.dart';
import '../../domain/services/error_diagnostics_service.dart';

/// Error Diagnostics Panel — "The Forensics Lab".
///
/// Transforms cryptic errors into actionable intelligence.
/// Shows pattern detection, confidence-rated diagnosis,
/// and recommended actions.
///
/// Can be used inline (in download card) or standalone (full view).
class ErrorDiagnosticsPanel extends ConsumerWidget {
  final DownloadEntity download;
  final bool compact;

  const ErrorDiagnosticsPanel({
    super.key,
    required this.download,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(errorDiagnosticsProvider);
    final notifier = ref.read(errorDiagnosticsProvider.notifier);
    final diagnosis = notifier.diagnose(download);

    if (compact) {
      return _CompactDiagnosis(diagnosis: diagnosis, download: download);
    }

    return _FullDiagnosis(
      diagnosis: diagnosis,
      download: download,
      recentCount: diagnostics.recentIncidents.length,
    );
  }
}

/// Compact inline diagnosis — fits inside a download card.
class _CompactDiagnosis extends StatelessWidget {
  final ErrorDiagnosis diagnosis;
  final DownloadEntity download;

  const _CompactDiagnosis({
    required this.diagnosis,
    required this.download,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPattern = diagnosis.pattern != null && diagnosis.pattern!.isHot;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1520).withAlpha(200)
            : const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark
              ? AppColors.accentHighlight.withAlpha(30)
              : AppColors.accentHighlight.withAlpha(15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Agent diagnosis label + confidence
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight.withAlpha(isDark ? 30 : 20),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'DIAGNOSIS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentHighlight,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                diagnosis.confidenceLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _confidenceColor(diagnosis.confidence),
                ),
              ),
              if (hasPattern) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'PATTERN',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warningAmber,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Diagnosis title
          Text(
            diagnosis.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 4),

          // Top recommended action + Report button
          Row(
            children: [
              if (diagnosis.actions.isNotEmpty) ...[
                Icon(
                  _actionIcon(diagnosis.actions.first.type),
                  size: 12,
                  color: AppColors.successGreen.withAlpha(180),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    diagnosis.actions.first.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFF666666),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: 6),
              _CompactReportButton(download: download),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full diagnosis view with all details.
class _FullDiagnosis extends StatelessWidget {
  final ErrorDiagnosis diagnosis;
  final DownloadEntity download;
  final int recentCount;

  const _FullDiagnosis({
    required this.diagnosis,
    required this.download,
    required this.recentCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPattern = diagnosis.pattern != null && diagnosis.pattern!.isHot;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF151118)
            : const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark
              ? AppColors.accentHighlight.withAlpha(25)
              : AppColors.accentHighlight.withAlpha(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar with wine-red accent
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.smMd,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accentHighlight.withAlpha(isDark ? 20 : 10),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.biotech,
                  size: 18,
                  color: AppColors.accentHighlight,
                ),
                const SizedBox(width: 8),
                Text(
                  'Error Forensics',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFE0E0E0)
                        : const Color(0xFF333333),
                  ),
                ),
                const Spacer(),
                // Confidence meter
                _ConfidenceBadge(confidence: diagnosis.confidence),
              ],
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error code + icon
                Row(
                  children: [
                    Icon(
                      download.errorCode?.icon ?? Icons.error_outline,
                      size: 20,
                      color: AppColors.errorRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        diagnosis.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? const Color(0xFFF0F0F0)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.smMd),

                // Pattern alert
                if (hasPattern)
                  _PatternAlert(pattern: diagnosis.pattern!),

                if (hasPattern)
                  const SizedBox(height: AppSpacing.smMd),

                // Explanation
                Text(
                  diagnosis.explanation,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark
                        ? const Color(0xFFB0B0B0)
                        : const Color(0xFF555555),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Recommended actions
                if (diagnosis.actions.isNotEmpty) ...[
                  Text(
                    'RECOMMENDED ACTIONS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF999999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...diagnosis.actions.map(
                    (action) => _ActionTile(action: action),
                  ),
                ],

                // Stats footer
                if (recentCount > 0) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$recentCount errors in the last 24h',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFFAAAAAA),
                    ),
                  ),
                ],

                // Escalation actions
                const SizedBox(height: AppSpacing.smMd),
                Row(
                  children: [
                    Expanded(
                      child: _EscalateButton(
                        icon: Icons.flag_outlined,
                        label: AppLocalizations.assistantDiagnosticsReportBug,
                        onTap: () => BugReportDialog.show(
                          context,
                          downloadContext: download,
                        ),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _EscalateButton(
                        icon: Icons.support_agent_outlined,
                        label: AppLocalizations.assistantDiagnosticsGetHelp,
                        primary: true,
                        onTap: () => _openHelpTicket(
                          context,
                          download,
                          diagnosis,
                        ),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confidence badge — color-coded percentage.
class _ConfidenceBadge extends StatelessWidget {
  final double confidence;

  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _confidenceColor(confidence);
    final pct = (confidence * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 25 : 15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$pct% confident',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pattern alert banner — shown when a hot pattern is detected.
class _PatternAlert extends StatelessWidget {
  final ErrorPattern pattern;

  const _PatternAlert({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warningAmber.withAlpha(15)
            : AppColors.warningAmber.withAlpha(10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.warningAmber.withAlpha(isDark ? 40 : 25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.trending_up,
            size: 14,
            color: AppColors.warningAmber,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${pattern.occurrences} occurrences '
              '${pattern.platform != null ? 'from ${pattern.platform}' : 'across platforms'} '
              'in ${pattern.timeSpan}'
              '${pattern.autoHealedCount > 0 ? ' · ${pattern.autoHealedCount} auto-healed' : ''}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.warningAmber
                    : const Color(0xFF92600A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single recommended action tile.
class _ActionTile extends StatelessWidget {
  final RecommendedAction action;

  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _actionColor(action.type).withAlpha(isDark ? 25 : 15),
            ),
            child: Icon(
              _actionIcon(action.type),
              size: 12,
              color: _actionColor(action.type),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFDDDDDD)
                        : const Color(0xFF333333),
                  ),
                ),
                Text(
                  action.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF999999)
                        : const Color(0xFF777777),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STANDALONE DIAGNOSTICS OVERVIEW — for Settings or Agent view
// =============================================================================

/// Overview of all error patterns and diagnostics.
/// Shown in the Agent Control Panel or as a standalone section.
class ErrorDiagnosticsOverview extends ConsumerWidget {
  const ErrorDiagnosticsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(errorDiagnosticsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (diagnostics.totalIncidents == 0) {
      return _EmptyState(isDark: isDark);
    }

    final hotPatterns = diagnostics.hotPatterns;
    final healRate = diagnostics.overallHealRate;
    final recent = diagnostics.recentIncidents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats row
        Row(
          children: [
            _StatChip(
              label: AppLocalizations.assistantDiagnosticsStat24hErrors,
              value: '${recent.length}',
              color: recent.isNotEmpty ? AppColors.errorRed : AppColors.successGreen,
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _StatChip(
              label: AppLocalizations.assistantDiagnosticsStatHealRate,
              value: '${(healRate * 100).round()}%',
              color: healRate > 0.5
                  ? AppColors.successGreen
                  : (healRate > 0.2 ? AppColors.warningAmber : AppColors.errorRed),
              isDark: isDark,
            ),
            const SizedBox(width: 8),
            _StatChip(
              label: AppLocalizations.assistantDiagnosticsStatPatterns,
              value: '${hotPatterns.length}',
              color: hotPatterns.isNotEmpty
                  ? AppColors.warningAmber
                  : AppColors.successGreen,
              isDark: isDark,
            ),
          ],
        ),

        if (hotPatterns.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.smMd),
          ...hotPatterns.take(3).map(
                (pattern) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _PatternAlert(pattern: pattern),
                ),
              ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;

  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 16,
          color: AppColors.successGreen,
        ),
        const SizedBox(width: 8),
        Text(
          'No errors recorded. All clear.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF999999) : const Color(0xFF777777),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 20 : 12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF999999) : const Color(0xFF777777),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "Report" button inside the diagnostics panel.
class _CompactReportButton extends StatelessWidget {
  final DownloadEntity download;

  const _CompactReportButton({required this.download});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => BugReportDialog.show(context, downloadContext: download),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accentHighlight.withAlpha(isDark ? 25 : 15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: AppColors.accentHighlight.withAlpha(isDark ? 50 : 30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.flag_outlined,
                size: 10,
                color: AppColors.accentHighlight,
              ),
              const SizedBox(width: 3),
              Text(
                'REPORT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentHighlight,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escalation button — "Report Bug" or "Get Help".
class _EscalateButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool primary;

  const _EscalateButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = primary ? AppColors.accentHighlight : (isDark ? const Color(0xFF999999) : const Color(0xFF666666));

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: primary
                ? AppColors.accentHighlight.withAlpha(isDark ? 25 : 15)
                : (isDark ? const Color(0xFF222222) : const Color(0xFFF0F0F0)),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: primary
                  ? AppColors.accentHighlight.withAlpha(isDark ? 50 : 30)
                  : (isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a pre-filled support ticket from error diagnostics context.
void _openHelpTicket(
  BuildContext context,
  DownloadEntity download,
  ErrorDiagnosis diagnosis,
) {
  final subject = StringBuffer();
  if (download.errorCode != null) {
    subject.write('[${download.platform}] ${download.errorCode!.name}');
  } else {
    subject.write('[${download.platform}] Download error');
  }
  subject.write(' — ${download.title ?? download.filename}');

  final message = StringBuffer();
  message.writeln('**Error:** ${download.errorCode?.name ?? "unknown"}');
  message.writeln('**URL:** ${download.url}');
  message.writeln('**Platform:** ${download.platform}');
  message.writeln('**Download Method:** ${download.downloadMethod}');
  if (download.errorDetail != null) {
    message.writeln('**Error Detail:** ${download.errorDetail}');
  }
  if (download.qualityLabel != null) {
    message.writeln('**Quality:** ${download.qualityLabel}');
  }
  if (download.retryCount > 0) {
    message.writeln('**Retry Count:** ${download.retryCount}');
  }
  message.writeln();
  message.writeln('**AI Diagnosis:** ${diagnosis.title}');
  message.writeln('**Confidence:** ${(diagnosis.confidence * 100).round()}%');
  message.writeln('**Explanation:** ${diagnosis.explanation}');
  if (diagnosis.pattern != null && diagnosis.pattern!.isHot) {
    final p = diagnosis.pattern!;
    message.writeln(
      '**Pattern:** ${p.occurrences}x in ${p.timeSpan} '
      '(${(p.healRate * 100).round()}% auto-healed)',
    );
  }
  if (diagnosis.actions.isNotEmpty) {
    message.writeln();
    message.writeln('**Recommended actions tried:**');
    for (final action in diagnosis.actions) {
      message.writeln('- ${action.label}: ${action.description}');
    }
  }
  message.writeln();
  message.writeln('---');
  message.writeln('*Auto-generated from error diagnostics*');

  showDialog(
    context: context,
    builder: (_) => CreateTicketDialog(
      onCreated: () {},
      initialSubject: subject.toString(),
      initialMessage: message.toString(),
      initialCategory: 'technical',
    ),
  );
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

Color _confidenceColor(double confidence) {
  if (confidence >= 0.85) return AppColors.successGreen;
  if (confidence >= 0.65) return AppColors.warningAmber;
  return AppColors.errorRed;
}

IconData _actionIcon(RecommendedActionType type) => switch (type) {
      RecommendedActionType.autoRetry => Icons.refresh,
      RecommendedActionType.updateYtdlp => Icons.system_update,
      RecommendedActionType.checkNetwork => Icons.wifi_find,
      RecommendedActionType.useVpn => Icons.vpn_key,
      RecommendedActionType.addCookies => Icons.cookie,
      RecommendedActionType.changeSavePath => Icons.folder_open,
      RecommendedActionType.freeDiskSpace => Icons.cleaning_services,
      RecommendedActionType.tryAlternateQuality => Icons.tune,
      RecommendedActionType.waitAndRetry => Icons.schedule,
      RecommendedActionType.manualRetry => Icons.replay,
    };

Color _actionColor(RecommendedActionType type) => switch (type) {
      RecommendedActionType.autoRetry => AppColors.successGreen,
      RecommendedActionType.updateYtdlp => AppColors.infoBlue,
      RecommendedActionType.checkNetwork => AppColors.warningAmber,
      RecommendedActionType.useVpn => AppColors.infoBlue,
      RecommendedActionType.addCookies => AppColors.warningAmber,
      RecommendedActionType.changeSavePath => AppColors.infoBlue,
      RecommendedActionType.freeDiskSpace => AppColors.warningAmber,
      RecommendedActionType.tryAlternateQuality => AppColors.infoBlue,
      RecommendedActionType.waitAndRetry => AppColors.warningAmber,
      RecommendedActionType.manualRetry => AppColors.infoBlue,
    };
