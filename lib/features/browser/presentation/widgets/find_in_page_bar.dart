import '../../../../core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Overlay bar for find-in-page functionality.
///
/// Shows a text field, match count, and prev/next navigation buttons.
/// Animated slide-in from top.
class FindInPageBar extends StatefulWidget {
  const FindInPageBar({
    super.key,
    required this.onSearch,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    this.currentMatch = 0,
    this.totalMatches = 0,
  });

  final ValueChanged<String> onSearch;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final int currentMatch;
  final int totalMatches;

  @override
  State<FindInPageBar> createState() => FindInPageBarState();
}

class FindInPageBarState extends State<FindInPageBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();

    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Focus the search field (called externally when shortcut pressed again).
  void focus() {
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _onChanged(String value) {
    widget.onSearch(value);
  }

  void _close() {
    _animController.reverse().then((_) {
      widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SlideTransition(
      position: _slideAnimation,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: cs.outline.withValues(alpha: AppOpacity.scrim),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: AppOpacity.pressed),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.findInPagePlaceholder,
                      hintStyle: AppTypography.buttonSecondary.copyWith(
                        color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                        fontWeight: FontWeight.w400,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smMd,
                        vertical: AppSpacing.sm,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: AppOpacity.scrim),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: AppOpacity.scrim),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        borderSide:
                            BorderSide(color: AppColors.accentHighlight, width: 1.5),
                      ),
                      filled: true,
                      fillColor: cs.surface,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 20,
                      ),
                      isDense: true,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => widget.onNext(),
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // Match count
              if (_controller.text.isNotEmpty)
                SizedBox(
                  width: 72,
                  child: Text(
                    widget.totalMatches > 0
                        ? AppLocalizations.findInPageMatchCount(
                            widget.currentMatch + 1, widget.totalMatches)
                        : AppLocalizations.findInPageNoMatches,
                    style: AppTypography.metadata.copyWith(
                      color: widget.totalMatches > 0
                          ? cs.onSurface.withValues(alpha: AppOpacity.strong)
                          : cs.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Previous
              IconButton(
                onPressed:
                    widget.totalMatches > 0 ? widget.onPrevious : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                tooltip: AppLocalizations.findInPagePrevious,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),

              // Next
              IconButton(
                onPressed: widget.totalMatches > 0 ? widget.onNext : null,
                icon:
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                tooltip: AppLocalizations.findInPageNext,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),

              // Close
              IconButton(
                onPressed: _close,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: AppLocalizations.findInPageClose,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
