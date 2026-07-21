import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/providers/backend_providers.dart';
import '../providers/assistant_providers.dart';

/// Chat conversation view — "The Dialogue"
/// Glass card AI messages with wine-red accent, message actions, suggested chips
class AiChatView extends ConsumerStatefulWidget {
  final String sessionId;

  const AiChatView({super.key, required this.sessionId});

  @override
  ConsumerState<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends ConsumerState<AiChatView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(aiSessionDetailProvider(widget.sessionId));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Messages
        Expanded(
          child: sessionAsync.when(
            data: (session) {
              final messages = session.messages ?? [];
              if (messages.isEmpty) {
                return _buildEmptyState(isDark, theme);
              }

              if (!_didInitialScroll) {
                _didInitialScroll = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  // Stable per-message key — without it, ListView.builder reuses
                  // _MessageBubbleState by index. When messages stream/insert,
                  // MouseRegion in the stale state fires → mouse_tracker assertion.
                  return _MessageBubble(
                    key: ValueKey<String>('chat_msg_${msg.id}'),
                    message: msg,
                    isDark: isDark,
                  );
                },
              );
            },
            loading: () => Center(
              child: CircularProgressIndicator(
                color: AppColors.accentHighlight,
                strokeWidth: 2,
              ),
            ),
            error: (error, _) => _buildErrorState(isDark, theme),
          ),
        ),

        // Thinking indicator
        if (_isSending) _buildThinkingIndicator(isDark, theme),

        // Input area
        _buildInputArea(isDark, theme),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: AppColors.metaText(context),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            AppLocalizations.assistantNoMessages,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.metaText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: AppColors.errorRed),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.assistantLoadError,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.errorRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator(bool isDark, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface1 : AppColors.lightSurface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border(
              left: BorderSide(
                color: AppColors.brand,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThinkingDots(color: AppColors.accentHighlight),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppLocalizations.assistantThinking,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.metaText(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.smMd, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightBase,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: AppOpacity.divider)
                : Colors.black.withValues(alpha: AppOpacity.divider),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: AppLocalizations.assistantTypeMessage,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.metaText(context),
                ),
                filled: true,
                fillColor: isDark ? AppColors.darkSurface1 : AppColors.lightSurface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(color: AppColors.brand, width: 2),
                ),
                contentPadding: const EdgeInsets.fromLTRB(AppSpacing.mdLg, AppSpacing.smMd, AppSpacing.sm, AppSpacing.smMd),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: _isSending
                          ? (isDark ? AppColors.darkElevated : AppColors.lightSurface3)
                          : AppColors.accentHighlight,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                    ),
                  ),
                ),
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_isSending,
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
      final result = await service.sendAiMessage(widget.sessionId, content);

      result.when(
        success: (_) {
          ref.invalidate(aiSessionDetailProvider(widget.sessionId));
          _scrollToBottom();
        },
        failure: (e) {
          if (mounted) {
            AppSnackBar.error(context, message: AppLocalizations.assistantLoadError);
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

/// Individual message bubble with Nocturne styling
class _MessageBubble extends StatefulWidget {
  final ChatMessageResponse message;
  final bool isDark;

  const _MessageBubble({super.key, required this.message, required this.isDark});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = widget.message.role == 'user';
    final isDark = widget.isDark;

    return MouseRegion(
      onEnter: (_) { if (mounted) setState(() => _hovered = true); },
      onExit: (_) { if (mounted) setState(() => _hovered = false); },
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: AppSpacing.md,
            left: isUser ? 80 : 0,
            right: isUser ? 0 : 80,
          ),
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Sender label for AI
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.accentHighlight, AppColors.brand],
                          ),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${AppConstants.appName} AI',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.accentHighlight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Message card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
                decoration: BoxDecoration(
                  color: isUser
                      ? (isDark ? AppColors.brand : AppColors.brand)
                      : (isDark ? AppColors.darkSurface1 : AppColors.lightElevated),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(3),
                    topRight: const Radius.circular(3),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border(
                          left: BorderSide(
                            color: AppColors.brand,
                            width: 2,
                          ),
                        ),
                  boxShadow: !isDark && !isUser
                      ? [
                          BoxShadow(
                            color: AppColors.brand.withValues(alpha: AppOpacity.divider),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: isUser
                  ? SelectableText(
                      widget.message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        height: 1.5,
                      ),
                    )
                  : _MarkdownText(
                      content: widget.message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppColors.darkLightText : AppColors.darkSurface1,
                        height: 1.5,
                      ) ?? const TextStyle(),
                      boldColor: isDark ? Colors.white : const Color(0xFF0A0A0A),
                      codeBackground: isDark
                          ? AppColors.darkElevated
                          : AppColors.lightSurface3,
                    ),
              ),

              // Bottom row: timestamp + actions
              Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: isUser ? 0 : AppSpacing.md,
                  right: isUser ? AppSpacing.md : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.message.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.metaText(context),
                      ),
                    ),
                    // Copy action — always mounted for AI messages; opacity-toggled on hover.
                    // Conditional mounting on _hovered triggers mouse_tracker.dart:203
                    // assertion when ListView rebuilds during pointer dispatch.
                    if (!isUser) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _hovered ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !_hovered,
                          child: _CopyButton(
                            text: widget.message.content,
                            isDark: isDark,
                            copied: _copied,
                            onCopied: () {
                              setState(() => _copied = true);
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _copied = false);
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}

/// Copy-to-clipboard action button
class _CopyButton extends StatelessWidget {
  final String text;
  final bool isDark;
  final bool copied;
  final VoidCallback onCopied;

  const _CopyButton({
    required this.text,
    required this.isDark,
    required this.copied,
    required this.onCopied,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ClipboardService.setText(text);
        onCopied();
      },
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              copied ? Icons.check : Icons.copy,
              size: 12,
              color: copied
                  ? AppColors.successGreen
                  : AppColors.metaText(context),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              copied
                  ? AppLocalizations.assistantMessageCopied
                  : AppLocalizations.assistantCopyMessage,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: copied
                    ? AppColors.successGreen
                    : AppColors.metaText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight markdown text renderer for AI responses
/// Supports: **bold**, *italic*, `inline code`, numbered lists, bullet lists
class _MarkdownText extends StatelessWidget {
  final String content;
  final TextStyle style;
  final Color boldColor;
  final Color codeBackground;

  const _MarkdownText({
    required this.content,
    required this.style,
    required this.boldColor,
    required this.codeBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _parse(content)),
      style: style,
    );
  }

  List<InlineSpan> _parse(String text) {
    final spans = <InlineSpan>[];
    // Regex: **bold**, *italic*, `code`, or plain text
    final pattern = RegExp(
      r'\*\*(.+?)\*\*'  // **bold**
      r'|\*(.+?)\*'     // *italic*
      r'|`(.+?)`'       // `code`
      r'|([^*`]+)',      // plain text
    );

    for (final match in pattern.allMatches(text)) {
      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(1),
          style: TextStyle(fontWeight: FontWeight.w700, color: boldColor),
        ));
      } else if (match.group(2) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(3) != null) {
        // `code`
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: codeBackground,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              match.group(3)!,
              style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: (style.fontSize ?? 14) - 1,
              ),
            ),
          ),
        ));
      } else if (match.group(4) != null) {
        // plain text
        spans.add(TextSpan(text: match.group(4)));
      }
    }

    return spans;
  }
}

/// Animated three-dot thinking indicator
class _ThinkingDots extends StatefulWidget {
  final Color color;
  const _ThinkingDots({required this.color});

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
    });

    _animations = _controllers.map((c) {
      return Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (_, __) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                  alpha: AppOpacity.scrim + (_animations[i].value * AppOpacity.strong),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
