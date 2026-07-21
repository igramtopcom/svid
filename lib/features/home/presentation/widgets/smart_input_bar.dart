/// V2 — Smart input bar (composite). **DORMANT V2 SCAFFOLD.**
///
/// This widget was Phase 1A's full replacement for the v1
/// [GlassmorphismHeader]. The current production code path **does not
/// render this widget** — V2 features (smart classify routing,
/// adaptive CTA label, sheet routing) ship by augmenting
/// `glassmorphism_header.dart` directly, so the home shell preserves
/// paste pill / clipboard radar / extraction state UX.
///
/// Why kept:
///   - Re-introducing a fully-V2 home (gated by
///     [FeatureFlags.homeV2Enabled]) lets us swap GlassmorphismHeader
///     out for SmartInputBar without re-implementing classification,
///     debouncing, popover state — they're already wired here and
///     analyzer-clean.
///   - Sub-widgets (smart_cta_button, customize_icon_button,
///     preset_dropdown_button, preset_popover) are tested call sites
///     that would be expensive to recreate from spec.
///
/// If the team's V2 strategy permanently shifts away from a
/// SmartInputBar replacement, delete this file *and* the sub-widgets
/// listed above *and* update [FeatureFlags] documentation.
///
/// Top-level control row layout per UI Spec §4:
///
///   [Input link / từ khóa] [History] [Batch] [⚙️ Customize] [Preset ▾] [CTA]
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_tokens.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../domain/services/url_classifier_service.dart';
import '../providers/customize_preferences_provider.dart';
import '../providers/smart_input_provider.dart';
import 'customize_icon_button.dart';
import 'preset_dropdown_button.dart';
import 'preset_popover.dart';
import 'smart_cta_button.dart';

/// Callbacks the parent screen plugs in. All optional — empty handlers
/// produce a passive bar (useful for previews / tests).
class SmartInputCallbacks {
  const SmartInputCallbacks({
    this.onSubmitSingleVideo,
    this.onSubmitMultipleUrls,
    this.onOpenChannelSheet,
    this.onOpenPlaylistSheet,
    this.onOpenSearchSheet,
    this.onOpenBrowser,
    this.onPressHistory,
    this.onPressBatch,
    this.onPressCustomize,
    this.onOpenAdvancedSettings,
    this.onCreateProfile,
  });

  final ValueChanged<String>? onSubmitSingleVideo;
  final ValueChanged<List<String>>? onSubmitMultipleUrls;
  final ValueChanged<String>? onOpenChannelSheet;
  final ValueChanged<String>? onOpenPlaylistSheet;
  final ValueChanged<String>? onOpenSearchSheet;
  final ValueChanged<String>? onOpenBrowser;
  final VoidCallback? onPressHistory;
  final VoidCallback? onPressBatch;
  final ValueChanged<String>? onPressCustomize;
  final VoidCallback? onOpenAdvancedSettings;
  final VoidCallback? onCreateProfile;
}

class SmartInputBar extends ConsumerStatefulWidget {
  const SmartInputBar({
    this.callbacks = const SmartInputCallbacks(),
    this.presetLabel = 'MP4 · 1080p',
    super.key,
  });

  final SmartInputCallbacks callbacks;
  final String presetLabel;

  @override
  ConsumerState<SmartInputBar> createState() => _SmartInputBarState();
}

class _SmartInputBarState extends ConsumerState<SmartInputBar> {
  late final TextEditingController _textController;
  final GlobalKey _presetButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    ref.read(smartInputProvider.notifier).update(_textController.text);
  }

  void _onSubmit() {
    // Force-flush the debounce so we never act on a stale classification.
    ref.read(smartInputProvider.notifier).flush();
    final state = ref.read(smartInputProvider);
    final raw = state.rawText.trim();
    if (raw.isEmpty) return;

    final cb = widget.callbacks;
    switch (state.type) {
      case SmartInputType.empty:
        return;
      case SmartInputType.singleVideo:
        cb.onSubmitSingleVideo?.call(raw);
        break;
      case SmartInputType.multipleUrls:
        final urls = raw
            .split(RegExp(r'[\s,]+'))
            .where((t) => t.isNotEmpty)
            .toList();
        cb.onSubmitMultipleUrls?.call(urls);
        break;
      case SmartInputType.playlist:
        cb.onOpenPlaylistSheet?.call(raw);
        break;
      case SmartInputType.channel:
        cb.onOpenChannelSheet?.call(raw);
        break;
      case SmartInputType.searchKeyword:
        cb.onOpenSearchSheet?.call(raw);
        break;
      case SmartInputType.unsupportedUrl:
        cb.onOpenBrowser?.call(raw);
        break;
    }
  }

  void _onCustomize() {
    final raw = _textController.text.trim();
    if (raw.isEmpty) return;
    widget.callbacks.onPressCustomize?.call(raw);
  }

  Future<void> _openPresetPopover() async {
    final box =
        _presetButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final intent = await showPresetPopover(context: context, anchor: box);
    if (!mounted || intent == null) return;
    switch (intent) {
      case PresetPopoverIntent.openAdvancedSettings:
        widget.callbacks.onOpenAdvancedSettings?.call();
        break;
      case PresetPopoverIntent.createNewProfile:
        widget.callbacks.onCreateProfile?.call();
        break;
      case PresetPopoverIntent.toggledDeepCustomize:
        // The toggle persists itself; no further action needed here.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartInputProvider);
    final deepCustomize = ref.watch(popoverDeepCustomizeProvider);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: AppMinWidth.actionBar),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _buildInputField(context)),
          const SizedBox(width: AppSpacing.sm),
          _IconButton(
            tooltip: AppLocalizations.homeDownloadsHistoryTab,
            icon: Icons.history,
            onPressed: widget.callbacks.onPressHistory,
          ),
          const SizedBox(width: AppSpacing.xs),
          _IconButton(
            tooltip: AppLocalizations.homeBatchDownloadTitle,
            icon: Icons.layers_outlined,
            onPressed: widget.callbacks.onPressBatch,
          ),
          const SizedBox(width: AppSpacing.xs),
          CustomizeIconButton(state: state, onPressed: _onCustomize),
          const SizedBox(width: AppSpacing.sm),
          KeyedSubtree(
            key: _presetButtonKey,
            child: PresetDropdownButton(
              label: widget.presetLabel,
              deepCustomizeActive: deepCustomize,
              onPressed: _openPresetPopover,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SmartCtaButton(state: state, onPressed: _onSubmit),
        ],
      ),
    );
  }

  Widget _buildInputField(BuildContext context) {
    return TextField(
      controller: _textController,
      onSubmitted: (_) => _onSubmit(),
      maxLines: 1,
      decoration: InputDecoration(
        hintText: AppLocalizations.homeUrlHint,
        prefixIcon: const Icon(Icons.link),
        suffixIcon: _textController.text.isEmpty
            ? null
            : IconButton(
                tooltip: AppLocalizations.commonClear,
                icon: const Icon(Icons.cancel, size: AppIconSize.lg),
                onPressed: () {
                  _textController.clear();
                  ref.read(smartInputProvider.notifier).clear();
                },
              ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppComponentSize.iconButtonSize,
      height: AppComponentSize.iconButtonSize,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: AppComponentSize.iconButtonGlyph),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            AppMinWidth.iconOnlyButton,
            AppMinWidth.iconOnlyButton,
          ),
        ),
      ),
    );
  }
}
