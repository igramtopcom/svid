import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../providers/support_providers.dart';

class TicketChatScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketChatScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends ConsumerState<TicketChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _refreshTimer;
  bool _isSending = false;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        ref.invalidate(ticketDetailProvider(widget.ticketId));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketDetailProvider(widget.ticketId));
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
                Expanded(
                  child: ticketAsync.when(
                    data:
                        (ticket) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ticket.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Row(
                              children: [
                                Text(
                                  _formatCategory(ticket.category),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(
                                          alpha: AppOpacity.secondary,
                                        ),
                                    letterSpacing: 0,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    '\u00B7',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ),
                                _StatusBadge(status: ticket.status),
                              ],
                            ),
                          ],
                        ),
                    loading:
                        () => Text(
                          AppLocalizations.supportTicketChat,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    error:
                        (_, __) => Text(
                          AppLocalizations.supportTicketChat,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),

          // Messages area
          Expanded(
            child: ColoredBox(
              color: pageBg,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ticketAsync.when(
                    data: (ticket) {
                      final messages = ticket.messages ?? [];
                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 40,
                                color: theme.colorScheme.outline.withValues(
                                  alpha: AppOpacity.scrim,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.smMd),
                              Text(
                                AppLocalizations.supportNoMessages,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!_didInitialScroll) {
                        _didInitialScroll = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(
                              _scrollController.position.maxScrollExtent,
                            );
                          }
                        });
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.mdLg,
                          AppSpacing.lg,
                          AppSpacing.mdLg,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isUser = msg.senderType == 'device';
                          final isSystem = msg.senderType == 'system';

                          // Stable per-message key — without it, MouseRegion State
                          // gets rebound on insert → mouse_tracker.dart:203 assertion.
                          if (isSystem) {
                            return KeyedSubtree(
                              key: ValueKey<String>('ticket_sys_${msg.id}'),
                              child: _buildSystemMessage(theme, msg.content),
                            );
                          }

                          return KeyedSubtree(
                            key: ValueKey<String>('ticket_msg_${msg.id}'),
                            child: _buildChatBubble(
                              theme: theme,
                              content: msg.content,
                              isUser: isUser,
                              time: _formatTime(msg.createdAt),
                            ),
                          );
                        },
                      );
                    },
                    loading:
                        () => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    error:
                        (error, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 36,
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
                                    () => ref.invalidate(
                                      ticketDetailProvider(widget.ticketId),
                                    ),
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

          // Message input
          Container(
            decoration: BoxDecoration(
              color:
                  isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context),
              border: Border(
                top: BorderSide(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.border(context),
                ),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.supportTypeMessage,
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline.withValues(
                                alpha: AppOpacity.secondary,
                              ),
                            ),
                            filled: true,
                            fillColor: AppColors.surface2(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.border(context),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.border(context),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.accentHighlight,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.smMd,
                            ),
                          ),
                          maxLines: 3,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smMd),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          onPressed: _isSending ? null : _sendMessage,
                          icon:
                              _isSending
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.arrow_upward, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                _isSending
                                    ? AppColors.accentHighlight.withValues(
                                      alpha: AppOpacity.overlay,
                                    )
                                    : AppColors.accentHighlight,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(ThemeData theme, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.smMd),
      child: Center(
        child: Text(
          content,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline.withValues(
              alpha: AppOpacity.strong,
            ),
            fontStyle: FontStyle.italic,
            letterSpacing: 0,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildChatBubble({
    required ThemeData theme,
    required String content,
    required bool isUser,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender label + time
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${isUser ? "You" : "Admin"} \u00B7 $time',
              style: AppTypography.mini.copyWith(
                color: theme.colorScheme.outline.withValues(
                  alpha: AppOpacity.secondary,
                ),
                letterSpacing: 0,
              ),
            ),
          ),
          // Bubble
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.smMd,
                ),
                decoration: BoxDecoration(
                  color:
                      isUser
                          ? AppColors.brand.withValues(
                            alpha: AppOpacity.quarter,
                          )
                          : (theme.brightness == Brightness.dark
                              ? AppColors.homeDarkCardBg
                              : AppColors.surface1(context)),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color:
                        isUser
                            ? AppColors.accentHighlight.withValues(alpha: 0.28)
                            : (theme.brightness == Brightness.dark
                                ? AppColors.homeDarkBorderSubtle
                                : AppColors.border(context)),
                  ),
                ),
                child: Text(
                  content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final service = ref.read(backendServiceProvider);
      final result = await service.sendTicketMessage(widget.ticketId, content);

      result.when(
        success: (_) {
          ref.invalidate(ticketDetailProvider(widget.ticketId));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        },
        failure: (e) {
          if (mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.supportLoadError,
            );
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatCategory(String category) {
    return category
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, statusColor) = switch (status) {
      'open' => ('Open', AppColors.accentHighlight),
      'in_progress' => ('In Progress', AppColors.statusInProgress),
      'waiting_for_customer' => ('Waiting', AppColors.warningAmber),
      'resolved' => ('Resolved', AppColors.successGreen),
      'closed' => ('Closed', AppColors.statusQueued),
      _ => (status.replaceAll('_', ' '), AppColors.statusQueued),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: statusColor.withValues(alpha: isDark ? 0.34 : 0.26),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.mini.copyWith(
          color: statusColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
