import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../providers/assistant_providers.dart';
import '../widgets/ai_chat_view.dart';
import '../widgets/assistant_top_bar.dart';
import '../widgets/assistant_welcome_view.dart';
import '../widgets/chat_context_panel.dart';
import '../widgets/escalation_dialog.dart';
import '../widgets/history_panel.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  @override
  Widget build(BuildContext context) {
    final viewMode = ref.watch(assistantViewModeProvider);
    final activeChatId = ref.watch(activeAiChatProvider);
    final isInChat = activeChatId != null && viewMode == AssistantViewMode.chat;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    final sessionTitle =
        isInChat
            ? ref
                .watch(aiSessionDetailProvider(activeChatId))
                .whenOrNull(
                  data:
                      (s) =>
                          s.title.isNotEmpty
                              ? s.title
                              : AppLocalizations.assistantChat,
                )
            : null;

    final sessionStatus =
        isInChat
            ? ref
                .watch(aiSessionDetailProvider(activeChatId))
                .whenOrNull(data: (s) => s.status)
            : null;

    return ColoredBox(
      color: pageBg,
      child: Column(
        children: [
          AssistantTopBar(
            onHistoryTap: () => _switchToHistory(),
            onNewChat: () => _switchToWelcome(),
            onBack:
                (isInChat || viewMode == AssistantViewMode.history)
                    ? () => _switchToWelcome()
                    : null,
            sessionTitle:
                isInChat
                    ? (sessionTitle ?? AppLocalizations.assistantChat)
                    : null,
            isHistoryView: viewMode == AssistantViewMode.history,
            trailing: _buildTrailing(isInChat, sessionStatus, activeChatId),
          ),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildContent(viewMode, activeChatId, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildTrailing(
    bool isInChat,
    String? sessionStatus,
    String? activeChatId,
  ) {
    if (!isInChat) return null;

    if (sessionStatus == 'escalated') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.warningAmber.withValues(alpha: AppOpacity.pressed),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.support_agent,
                size: 14,
                color: AppColors.warningAmber,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.assistantEscalated,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.warningAmber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sessionStatus == 'active') {
      return TextButton.icon(
        onPressed: () => _showEscalationDialog(activeChatId!),
        icon: Icon(
          Icons.support_agent,
          size: 16,
          color: AppColors.muted(context),
        ),
        label: Text(
          AppLocalizations.assistantEscalate,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: AppColors.muted(context)),
        ),
      );
    }

    return null;
  }

  Widget _buildContent(
    AssistantViewMode viewMode,
    String? activeChatId,
    bool isDark,
  ) {
    switch (viewMode) {
      case AssistantViewMode.welcome:
        return AssistantWelcomeView(
          key: const ValueKey('welcome'),
          onSendMessage: _startNewChat,
        );

      case AssistantViewMode.chat:
        if (activeChatId == null) {
          // Fallback to welcome if no active chat
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(assistantViewModeProvider.notifier).state =
                AssistantViewMode.welcome;
          });
          return const SizedBox.shrink();
        }
        // 70/30 split: Chat + Context Panel
        return LayoutBuilder(
          key: ValueKey('chat_$activeChatId'),
          builder: (context, constraints) {
            final showContextPanel = constraints.maxWidth >= 980;

            return Row(
              children: [
                Expanded(flex: 7, child: AiChatView(sessionId: activeChatId)),
                if (showContextPanel)
                  ChatContextPanel(
                    sessionId: activeChatId,
                    onEscalate: () => _showEscalationDialog(activeChatId),
                  ),
              ],
            );
          },
        );

      case AssistantViewMode.history:
        return HistoryPanel(
          key: const ValueKey('history'),
          onSessionTap: (sessionId) {
            ref.read(activeAiChatProvider.notifier).state = sessionId;
            ref.read(assistantViewModeProvider.notifier).state =
                AssistantViewMode.chat;
          },
          onClose: () => _switchToWelcome(),
        );
    }
  }

  void _startNewChat(String message) async {
    final service = ref.read(backendServiceProvider);
    final result = await service.createAiSession(message);

    result.when(
      success: (session) {
        if (mounted) {
          ref.read(activeAiChatProvider.notifier).state = session.id;
          ref.read(assistantViewModeProvider.notifier).state =
              AssistantViewMode.chat;
          ref.invalidate(aiSessionsProvider);
        }
      },
      failure: (e) {
        if (mounted) {
          AppSnackBar.error(
            context,
            message: AppLocalizations.assistantLoadError,
          );
        }
      },
    );
  }

  void _switchToWelcome() {
    ref.read(activeAiChatProvider.notifier).state = null;
    ref.read(assistantViewModeProvider.notifier).state =
        AssistantViewMode.welcome;
  }

  void _switchToHistory() {
    ref.read(assistantViewModeProvider.notifier).state =
        AssistantViewMode.history;
  }

  void _showEscalationDialog(String sessionId) {
    showDialog(
      context: context,
      builder:
          (_) => EscalationDialog(
            sessionId: sessionId,
            onEscalated: (ticketId) {
              ref.invalidate(aiSessionDetailProvider(sessionId));
              ref.invalidate(aiSessionsProvider);
              if (ticketId != null && mounted) {
                AppSnackBar.success(
                  context,
                  message: AppLocalizations.assistantEscalatedSuccess,
                );
              }
            },
          ),
    );
  }
}
