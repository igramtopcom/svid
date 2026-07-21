import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../../../core/core.dart';
import '../../../youtube_search/presentation/providers/recent_searches_provider.dart';
import '../../domain/services/url_classifier_service.dart';
import '../providers/home_search_suggestions_provider.dart';
import 'command_bar_preset_chip.dart';

/// Glassmorphism header with blur effect
/// Modern design inspired by macOS Big Sur + iOS 15
/// Enhanced with drag & drop, animations, and better UX
class GlassmorphismHeader extends ConsumerStatefulWidget {
  final TextEditingController urlController;
  final FocusNode urlFocusNode;
  final GlobalKey<FormState> formKey;
  final bool isExtracting;
  final String? extractingUrl;
  final DateTime? extractionStartedAt;
  final VoidCallback onDownload;
  final VoidCallback onPaste;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onBatchDownload;
  final bool showAutoPasteIndicator;
  final VoidCallback? onAutoPasteAnimationDone;
  final int historyCount;

  const GlassmorphismHeader({
    super.key,
    required this.urlController,
    required this.urlFocusNode,
    required this.formKey,
    required this.isExtracting,
    this.extractingUrl,
    this.extractionStartedAt,
    required this.onDownload,
    required this.onPaste,
    this.onHistoryTap,
    this.onBatchDownload,
    this.showAutoPasteIndicator = false,
    this.onAutoPasteAnimationDone,
    this.historyCount = 0,
  });

  @override
  ConsumerState<GlassmorphismHeader> createState() =>
      _GlassmorphismHeaderState();
}

/// Compact icon command used by the V2 command bar's History + Batch slots.
/// The visible surface stays icon-only; the label is exposed through tooltip
/// and semantics so the primary command line does not become text-heavy.
class _IconColumnButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color iconColor;
  final Color hoverBg;
  final VoidCallback? onPressed;
  final int badgeCount;
  final double height;
  final double width;

  const _IconColumnButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.iconColor,
    required this.hoverBg,
    required this.onPressed,
    this.badgeCount = 0,
    this.height = 56,
    this.width = 62,
  });

  @override
  State<_IconColumnButton> createState() => _IconColumnButtonState();
}

class _IconColumnButtonState extends State<_IconColumnButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final neutralBorder =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant.withValues(alpha: 0.72);
    final iconFrameHoverBg = widget.hoverBg;
    final glyph = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(widget.icon, size: 20, color: widget.iconColor),
        if (widget.badgeCount > 0)
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              child: Text(
                widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                style: AppTypography.mini.copyWith(
                  color: AppColors.darkLightText,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor:
            widget.onPressed == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: Semantics(
          button: true,
          label: widget.label,
          child: GestureDetector(
            onTap: widget.onPressed,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: widget.width,
              height: widget.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Ghost/secondary: transparent by default so the primary
                // Download CTA stays the visual anchor; frame appears on hover.
                color: _hovered ? iconFrameHoverBg : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(
                  color:
                      _hovered
                          ? neutralBorder.withValues(alpha: isDark ? 0.82 : 1)
                          : Colors.transparent,
                  width: 1,
                ),
              ),
              child: glyph,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassmorphismHeaderState extends ConsumerState<GlassmorphismHeader>
    with TickerProviderStateMixin {
  static const double _wideCommandBreakpoint = 920;
  static const double _stackedCommandBreakpoint = 760;
  static const double _commandBarHeight = 52;
  static const double _commandBarHeightCompact = 48;
  static const double _presetChipWidth = 176;
  static const double _ctaWidth = 184;
  static const double _ctaWidthCompact = 168;

  bool _isHoveringPaste = false;
  // History + Batch hover state was used by the legacy IconButton
  // command-bar slots; the V2 vertical-stack [_IconColumnButton]
  // owns its own hover state now. Fields removed — restore them if
  // the inline-glyph-only style ever returns.
  bool _isHoveringDownload = false;
  bool _isDraggingOver = false;
  bool _isDisposed = false;
  final LayerLink _suggestionsLayerLink = LayerLink();
  final GlobalKey _urlInputAnchorKey = GlobalKey();
  OverlayEntry? _suggestionsOverlay;
  int _highlightedSuggestionIndex = -1;
  List<String> _currentSuggestionTexts = const [];
  late AnimationController _autoPasteController;
  late Animation<double> _autoPasteAnimation;
  late AnimationController _extractGlowController;
  late Animation<double> _extractGlowAnimation;
  Timer? _phaseTimer;
  int _extractionPhase = 0;

  @override
  void initState() {
    super.initState();
    widget.urlController.addListener(_onUrlInputChanged);
    widget.urlFocusNode.addListener(_onUrlFocusChanged);
    _autoPasteController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _autoPasteAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _autoPasteController, curve: Curves.easeInOut),
    );

    // Extraction breathing glow — smooth crimson pulse on TextField + header (2s)
    _extractGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _extractGlowAnimation = CurvedAnimation(
      parent: _extractGlowController,
      curve: Curves.easeInOut,
    );

    if (widget.isExtracting) {
      _extractGlowController.repeat(reverse: true);
    }
  }

  void _onUrlInputChanged() {
    if (_isDisposed || !mounted) return;
    setState(() {});
    _syncHomeSuggestions();
  }

  void _onUrlFocusChanged() {
    if (_isDisposed || !mounted) return;
    if (widget.urlFocusNode.hasFocus) {
      _syncHomeSuggestions();
    } else {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!_isDisposed && mounted && !widget.urlFocusNode.hasFocus) {
          _removeSuggestionsOverlay();
        }
      });
    }
  }

  bool _canShowSuggestionsForCurrentText() {
    if (!widget.urlFocusNode.hasFocus || widget.isExtracting) return false;
    final raw = widget.urlController.text;
    final type = const UrlClassifierService().classify(raw);
    return HomeSearchSuggestionsNotifier.shouldFetchOnlineSuggestions(
      raw,
      type,
    );
  }

  void _syncHomeSuggestions() {
    if (_canShowSuggestionsForCurrentText()) {
      ref
          .read(homeSearchSuggestionsProvider.notifier)
          .updateQuery(widget.urlController.text);
      _showSuggestionsOverlay();
    } else {
      ref.read(homeSearchSuggestionsProvider.notifier).clear();
      _removeSuggestionsOverlay();
    }
  }

  void _showSuggestionsOverlay() {
    if (_suggestionsOverlay != null) {
      _suggestionsOverlay!.markNeedsBuild();
      return;
    }
    _highlightedSuggestionIndex = -1;
    _suggestionsOverlay = OverlayEntry(
      builder: (_) => _buildSuggestionsOverlay(),
    );
    Overlay.of(context).insert(_suggestionsOverlay!);
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
    _highlightedSuggestionIndex = -1;
    _currentSuggestionTexts = const [];
  }

  void _selectSuggestion(String suggestion) {
    widget.urlController.text = suggestion;
    widget.urlController.selection = TextSelection.collapsed(
      offset: suggestion.length,
    );
    _removeSuggestionsOverlay();
    ref.read(homeSearchSuggestionsProvider.notifier).clear();
    widget.urlFocusNode.unfocus();
    widget.onDownload();
  }

  KeyEventResult _handleSuggestionKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_suggestionsOverlay == null || _currentSuggestionTexts.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _highlightedSuggestionIndex =
          (_highlightedSuggestionIndex + 1) % _currentSuggestionTexts.length;
      _suggestionsOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _highlightedSuggestionIndex =
          _highlightedSuggestionIndex <= 0
              ? _currentSuggestionTexts.length - 1
              : _highlightedSuggestionIndex - 1;
      _suggestionsOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeSuggestionsOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _highlightedSuggestionIndex >= 0 &&
        _highlightedSuggestionIndex < _currentSuggestionTexts.length) {
      _selectSuggestion(_currentSuggestionTexts[_highlightedSuggestionIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  static const List<({String needle, String platform})> _platformSignatures = [
    (needle: 'youtube.com', platform: 'youtube'),
    (needle: 'youtu.be', platform: 'youtube'),
    (needle: 'tiktok.com', platform: 'tiktok'),
    (needle: 'instagram.com', platform: 'instagram'),
    (needle: 'facebook.com', platform: 'facebook'),
    (needle: 'fb.watch', platform: 'facebook'),
    (needle: 'x.com/', platform: 'x'),
    (needle: 'twitter.com', platform: 'x'),
    (needle: 'reddit.com', platform: 'reddit'),
    (needle: 'pinterest.com', platform: 'pinterest'),
    (needle: 'pin.it', platform: 'pinterest'),
  ];

  String? _detectPlatform(String text) {
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    for (final sig in _platformSignatures) {
      if (lower.contains(sig.needle)) return sig.platform;
    }
    return null;
  }

  Color _neutralCommandBorder(bool isDark) {
    return isDark
        ? AppColors.homeDarkInputBorder
        : Colors.black.withValues(alpha: 0.16);
  }

  Widget _buildPastePill(
    BuildContext context, {
    required bool isDark,
    required Color ghostColor,
    required ColorScheme cs,
  }) {
    final fgBase = isDark ? AppColors.darkLightText : cs.onSurface;
    final fg =
        _isHoveringPaste
            ? AppColors.accentHighlight
            : fgBase.withValues(alpha: AppOpacity.secondary);
    final bg =
        _isHoveringPaste
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.hover)
            : (isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerHighest);
    final border =
        _isHoveringPaste
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.strong)
            : (isDark
                ? ghostColor.withValues(alpha: AppOpacity.subtle)
                : cs.outlineVariant.withValues(alpha: AppOpacity.quarter));

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _isHoveringPaste = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _isHoveringPaste = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPaste,
          child: Tooltip(
            message: AppLocalizations.homePasteTooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(color: border, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.content_paste_rounded, size: 13, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    Platform.isMacOS ? '⌘V' : 'Ctrl+V',
                    style: AppTypography.mini.copyWith(
                      fontWeight: AppTypography.semiBold,
                      letterSpacing: 0.5,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Classify the current text-field value via the shared
  /// [UrlClassifierService]. Used to drive the adaptive CTA label.
  SmartInputType _classifyCurrent() =>
      const UrlClassifierService().classify(widget.urlController.text);

  /// CTA label that follows the smart-input intent AND the actual
  /// dispatcher behaviour in [HomeDownloadMixin.startDownload]. The
  /// channel + playlist sheets are YouTube-only today; for non-YouTube
  /// channel/playlist URLs the dispatcher falls through to single-URL
  /// extraction, so the label has to read "Tải xuống" rather than
  /// "Mở kênh" — otherwise the affordance promises a sheet that never
  /// opens. Re-key once per-platform sheets land. Strings are i18n-
  /// keyed so all 15 production locales fall through to English when
  /// the Vietnamese origin is not yet translated.
  String _adaptiveCtaLabel() {
    switch (_classifyCurrent()) {
      case SmartInputType.searchKeyword:
        return AppLocalizations.homeCtaSearch;
      case SmartInputType.channel:
        return _detectPlatform(widget.urlController.text) == 'youtube'
            ? AppLocalizations.homeCtaViewChannel
            : AppLocalizations.homeStartDownload;
      case SmartInputType.playlist:
        return _detectPlatform(widget.urlController.text) == 'youtube'
            ? AppLocalizations.homeCtaViewPlaylist
            : AppLocalizations.homeStartDownload;
      case SmartInputType.multipleUrls:
        return AppLocalizations.homeCtaBatchDownload;
      case SmartInputType.unsupportedUrl:
        return AppLocalizations.homeCtaOpenBrowser;
      case SmartInputType.empty:
      case SmartInputType.singleVideo:
        return AppLocalizations.homeStartDownload;
    }
  }

  String _getExtractionPhaseText() {
    switch (_extractionPhase) {
      case 0:
        return AppLocalizations.homeExtractionAnalyzing;
      case 1:
        return AppLocalizations.homeExtractionExtracting;
      case 2:
        return AppLocalizations.homeExtractionFetching;
      default:
        return AppLocalizations.homeExtractionAlmostReady;
    }
  }

  Widget _buildUrlInput({
    required double height,
    required bool isDark,
    required ColorScheme cs,
    required Color ghostColor,
    required Color metadataColor,
    required Color neutralBorder,
    required double glow,
  }) {
    return CompositedTransformTarget(
      key: _urlInputAnchorKey,
      link: _suggestionsLayerLink,
      child: SizedBox(
        height: height,
        child: Focus(
          onKeyEvent: _handleSuggestionKeyEvent,
          child: DragTarget<String>(
            onWillAcceptWithDetails:
                (details) => Validators.isDownloadableUrl(details.data),
            onAcceptWithDetails: (details) {
              widget.urlController.text = details.data;
              widget.urlFocusNode.requestFocus();
            },
            onMove: (_) => setState(() => _isDraggingOver = true),
            onLeave: (_) => setState(() => _isDraggingOver = false),
            builder: (context, candidateData, rejectedData) {
              return AnimatedBuilder(
                animation: _autoPasteAnimation,
                builder: (context, child) {
                  BorderSide enabledBorderSide;
                  if (_autoPasteAnimation.value > 0) {
                    enabledBorderSide = BorderSide(
                      color:
                          Color.lerp(
                            Colors.transparent,
                            AppColors.accentHighlight,
                            _autoPasteAnimation.value,
                          )!,
                      width: 1.5,
                    );
                  } else if (widget.isExtracting) {
                    enabledBorderSide = BorderSide(
                      color:
                          Color.lerp(
                            AppColors.accentHighlight.withValues(
                              alpha: AppOpacity.quarter,
                            ),
                            AppColors.accentHighlight.withValues(
                              alpha: AppOpacity.strong,
                            ),
                            glow,
                          )!,
                      width: 1.0 + (glow * 0.5),
                    );
                  } else {
                    enabledBorderSide = BorderSide(
                      color: neutralBorder,
                      width: 1,
                    );
                  }

                  Color fillColor;
                  if (_isDraggingOver) {
                    fillColor = AppColors.brand.withValues(
                      alpha: AppOpacity.hover,
                    );
                  } else if (widget.isExtracting) {
                    final baseFill =
                        isDark
                            ? AppColors.homeDarkAppBg
                            : AppColors.lightSurface2;
                    fillColor =
                        Color.lerp(
                          baseFill,
                          AppColors.brand.withValues(
                            alpha:
                                isDark
                                    ? AppOpacity.pressed
                                    : AppOpacity.divider,
                          ),
                          glow,
                        )!;
                  } else {
                    // Subtle gray fill so the input reads as a distinct field
                    // inside the white command card (not white-on-white).
                    fillColor =
                        isDark
                            ? AppColors.homeDarkAppBg
                            : cs.surfaceContainer;
                  }

                  final detectedPlatform = _detectPlatform(
                    widget.urlController.text,
                  );
                  final fallbackPrefixColor =
                      widget.isExtracting
                          ? Color.lerp(
                            isDark ? metadataColor : cs.onSurfaceVariant,
                            AppColors.accentHighlight,
                            glow * 0.6,
                          )!
                          : (isDark ? metadataColor : cs.onSurfaceVariant);

                  return TextFormField(
                    controller: widget.urlController,
                    focusNode: widget.urlFocusNode,
                    textAlignVertical: TextAlignVertical.center,
                    style: AppTypography.input.copyWith(
                      fontSize: height < _commandBarHeight ? 15 : 16,
                      fontWeight: AppTypography.regular,
                      color: isDark ? AppColors.darkLightText : cs.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          _isDraggingOver
                              ? AppLocalizations.homeDropUrlHint
                              : AppLocalizations.homeUrlHint,
                      hintStyle: AppTypography.inputHint.copyWith(
                        fontSize: height < _commandBarHeight ? 15 : 16,
                        fontWeight: AppTypography.regular,
                        color:
                            isDark
                                ? AppColors.darkLightText.withValues(
                                  alpha: AppOpacity.secondary,
                                )
                                : cs.onSurface.withValues(
                                  alpha: AppOpacity.secondary,
                                ),
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child:
                            detectedPlatform != null
                                ? PlatformIcon(
                                  platform: detectedPlatform,
                                  size: 22,
                                )
                                : Icon(
                                  Icons.link_rounded,
                                  size: 22,
                                  color: fallbackPrefixColor,
                                ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      suffixIcon:
                          widget.urlController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 18,
                                  color:
                                      isDark
                                          ? metadataColor
                                          : cs.onSurfaceVariant,
                                ),
                                onPressed: () {
                                  widget.urlController.clear();
                                  ref
                                      .read(
                                        homeSearchSuggestionsProvider.notifier,
                                      )
                                      .clear();
                                  _removeSuggestionsOverlay();
                                },
                                tooltip: AppLocalizations.homeClear,
                              )
                              : _buildPastePill(
                                context,
                                isDark: isDark,
                                ghostColor: ghostColor,
                                cs: cs,
                              ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      filled: true,
                      fillColor: fillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: enabledBorderSide,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(
                          color: AppColors.accentHighlight.withValues(
                            alpha: isDark ? AppOpacity.strong : 0.7,
                          ),
                          width: 1.25,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(color: cs.error, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(color: cs.error, width: 1.5),
                      ),
                      errorStyle: const TextStyle(fontSize: 0, height: 0),
                      errorMaxLines: 1,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.md + 2,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLocalizations.homeUrlRequired;
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => widget.onDownload(),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadCta({
    required double height,
    required double? width,
    required Color primaryCta,
    required Color primaryCtaHover,
    required Color primaryCtaDisabled,
  }) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHoveringDownload = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHoveringDownload = false);
      },
      child: SizedBox(
        width: width,
        height: height,
        child: FilledButton.icon(
          onPressed: widget.isExtracting ? null : widget.onDownload,
          icon:
              widget.isExtracting
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.darkLightText,
                      ),
                    ),
                  )
                  : const Icon(Icons.download_rounded, size: 20),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              widget.isExtracting
                  ? _getExtractionPhaseText()
                  : _adaptiveCtaLabel(),
              key: ValueKey(
                widget.isExtracting
                    ? 'extract-$_extractionPhase'
                    : 'idle-${_classifyCurrent().name}',
              ),
              style: AppTypography.buttonPrimary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                _isHoveringDownload && !widget.isExtracting
                    ? primaryCtaHover
                    : primaryCta,
            foregroundColor: AppColors.darkLightText,
            disabledBackgroundColor: primaryCtaDisabled,
            disabledForegroundColor: primaryCta,
            minimumSize: Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveCommandBar({
    required BoxConstraints constraints,
    required bool isDark,
    required ColorScheme cs,
    required Color ghostColor,
    required Color metadataColor,
    required Color iconColor,
    required Color iconHoverBg,
    required Color neutralBorder,
    required double glow,
    required Color primaryCta,
    required Color primaryCtaHover,
    required Color primaryCtaDisabled,
  }) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 1200.0;
    final isStacked = width < _stackedCommandBreakpoint;
    final isCompact = width < _wideCommandBreakpoint;
    final height = isCompact ? _commandBarHeightCompact : _commandBarHeight;
    final ctaWidth = isCompact ? _ctaWidthCompact : _ctaWidth;

    final input = _buildUrlInput(
      height: height,
      isDark: isDark,
      cs: cs,
      ghostColor: ghostColor,
      metadataColor: metadataColor,
      neutralBorder: neutralBorder,
      glow: glow,
    );

    final historyButton = _IconColumnButton(
      icon: Icons.schedule_outlined,
      label: AppLocalizations.homeHistoryButton,
      tooltip: AppLocalizations.homeExtractionHistoryTooltip,
      iconColor: iconColor,
      hoverBg: iconHoverBg,
      onPressed: widget.onHistoryTap,
      badgeCount: widget.historyCount,
      height: height,
      width: isCompact ? 56 : 58,
    );

    final batchButton = _IconColumnButton(
      icon: Icons.layers_outlined,
      label: AppLocalizations.homeBatchButton,
      tooltip: AppLocalizations.homeBatchButtonTooltip,
      iconColor: iconColor,
      hoverBg: iconHoverBg,
      onPressed: widget.onBatchDownload,
      height: height,
      width: isCompact ? 56 : 58,
    );

    final presetChip = SizedBox(
      width: _presetChipWidth,
      child: CommandBarPresetChip(height: height),
    );

    if (isStacked) {
      final shouldStretchCta = width < 500;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          input,
          const SizedBox(height: AppSpacing.smMd),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: shouldStretchCta ? width : ctaWidth,
                child: _buildDownloadCta(
                  height: height,
                  width: null,
                  primaryCta: primaryCta,
                  primaryCtaHover: primaryCtaHover,
                  primaryCtaDisabled: primaryCtaDisabled,
                ),
              ),
              presetChip,
              historyButton,
              batchButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: input),
        SizedBox(width: isCompact ? AppSpacing.sm : AppSpacing.smMd),
        // Primary action sits right next to the input for a tight
        // paste → download motion; secondary options trail after it.
        _buildDownloadCta(
          height: height,
          width: ctaWidth,
          primaryCta: primaryCta,
          primaryCtaHover: primaryCtaHover,
          primaryCtaDisabled: primaryCtaDisabled,
        ),
        SizedBox(width: isCompact ? AppSpacing.md : AppSpacing.mdLg),
        presetChip,
        const SizedBox(width: AppSpacing.sm),
        historyButton,
        const SizedBox(width: AppSpacing.sm),
        batchButton,
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    widget.urlController.removeListener(_onUrlInputChanged);
    widget.urlFocusNode.removeListener(_onUrlFocusChanged);
    _removeSuggestionsOverlay();
    _phaseTimer?.cancel();
    _autoPasteController.dispose();
    _extractGlowController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassmorphismHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlController != widget.urlController) {
      oldWidget.urlController.removeListener(_onUrlInputChanged);
      widget.urlController.addListener(_onUrlInputChanged);
    }
    if (oldWidget.urlFocusNode != widget.urlFocusNode) {
      oldWidget.urlFocusNode.removeListener(_onUrlFocusChanged);
      widget.urlFocusNode.addListener(_onUrlFocusChanged);
    }
    if (widget.showAutoPasteIndicator &&
        !oldWidget.showAutoPasteIndicator &&
        !_isDisposed) {
      _autoPasteController.forward(from: 0).then((_) {
        if (_isDisposed) return;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_isDisposed || !mounted) return;
          _autoPasteController.reverse().then((_) {
            if (!_isDisposed && mounted) {
              widget.onAutoPasteAnimationDone?.call();
            }
          });
        });
      });
    }
    // Start or stop phase rotation + extraction glow
    if (widget.isExtracting && !oldWidget.isExtracting) {
      _extractionPhase = 0;
      _phaseTimer?.cancel();
      _phaseTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_isDisposed && mounted) {
          setState(() {
            // Rotate through phases 0→1→2→3, hold at 3
            if (_extractionPhase < 3) _extractionPhase++;
          });
        }
      });
      _extractGlowController.repeat(reverse: true);
    } else if (!widget.isExtracting && oldWidget.isExtracting) {
      _phaseTimer?.cancel();
      _phaseTimer = null;
      _extractionPhase = 0;
      _extractGlowController.stop();
      _extractGlowController.reset();
    }
    if (widget.isExtracting && !oldWidget.isExtracting) {
      _removeSuggestionsOverlay();
    }
  }

  Widget _buildSuggestionsOverlay() {
    final anchorBox =
        _urlInputAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    final width = anchorBox?.size.width ?? 520.0;
    final anchorHeight = anchorBox?.size.height ?? _commandBarHeight;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final suggestionState = ref.watch(homeSearchSuggestionsProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final query = widget.urlController.text.trim().toLowerCase();
    final onlineItems = suggestionState.suggestions
        .take(8)
        .map((text) => (text: text, isRecent: false));
    final recentItems = (recentSearches.valueOrNull ?? const <String>[])
        .where((text) {
          if (query.isEmpty) return false;
          return text.toLowerCase().contains(query);
        })
        .take(5)
        .map((text) => (text: text, isRecent: true));

    final items =
        onlineItems.isNotEmpty ? onlineItems.toList() : recentItems.toList();
    _currentSuggestionTexts = items.map((item) => item.text).toList();
    if (_highlightedSuggestionIndex >= _currentSuggestionTexts.length) {
      _highlightedSuggestionIndex = _currentSuggestionTexts.length - 1;
    }

    final hasContent = items.isNotEmpty;
    if (!hasContent && !suggestionState.isLoading) {
      return const SizedBox.shrink();
    }

    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _suggestionsLayerLink,
        showWhenUnlinked: false,
        offset: Offset(0, anchorHeight + 6),
        child: Material(
          color: Colors.transparent,
          elevation: isDark ? 18 : 10,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: isDark ? AppColors.homeDarkCardBg : cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : cs.outlineVariant.withValues(alpha: 0.55),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
                  blurRadius: isDark ? 24 : 18,
                  offset: const Offset(0, 12),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child:
                  suggestionState.isLoading && !hasContent
                      ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.smMd),
                            Text(
                              AppLocalizations.commonLoading,
                              style: AppTypography.metadata.copyWith(
                                color:
                                    isDark
                                        ? AppColors.homeDarkTextSecondary
                                        : cs.onSurfaceVariant,
                                fontWeight: AppTypography.medium,
                              ),
                            ),
                          ],
                        ),
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.smMd,
                              AppSpacing.md,
                              AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  items.first.isRecent
                                      ? Icons.history_rounded
                                      : Icons.auto_awesome_rounded,
                                  size: 14,
                                  color:
                                      isDark
                                          ? AppColors.homeDarkTextMuted
                                          : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  items.first.isRecent
                                      ? AppLocalizations
                                          .youtubeSearchRecentSearches
                                      : AppLocalizations
                                          .youtubeSearchSuggestions,
                                  style: AppTypography.metadata.copyWith(
                                    color:
                                        isDark
                                            ? AppColors.homeDarkTextMuted
                                            : cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return _buildSuggestionRow(
                                  text: item.text,
                                  isRecent: item.isRecent,
                                  isHighlighted:
                                      index == _highlightedSuggestionIndex,
                                  onHover: () {
                                    _highlightedSuggestionIndex = index;
                                    _suggestionsOverlay?.markNeedsBuild();
                                  },
                                  onTap: () => _selectSuggestion(item.text),
                                );
                              },
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? AppColors.homeDarkAppBg
                                      : cs.surfaceContainerLowest,
                              border: Border(
                                top: BorderSide(
                                  color:
                                      isDark
                                          ? AppColors.homeDarkBorderStrong
                                          : cs.outlineVariant.withValues(
                                            alpha: AppOpacity.quarter,
                                          ),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.keyboard_rounded,
                                  size: 14,
                                  color:
                                      isDark
                                          ? AppColors.homeDarkTextSecondary
                                          : cs.onSurfaceVariant.withValues(
                                            alpha: AppOpacity.secondary,
                                          ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '↑↓ navigate   Enter select   Esc close',
                                  style: AppTypography.metadata.copyWith(
                                    color:
                                        isDark
                                            ? AppColors.homeDarkTextMuted
                                            : cs.onSurfaceVariant.withValues(
                                              alpha: AppOpacity.secondary,
                                            ),
                                    fontWeight: AppTypography.medium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionRow({
    required String text,
    required bool isRecent,
    required bool isHighlighted,
    required VoidCallback onHover,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentHighlight : AppColors.brand;
    final foreground = isDark ? AppColors.darkLightText : cs.onSurface;
    final muted =
        isDark
            ? AppColors.homeDarkTextMuted
            : cs.onSurfaceVariant.withValues(alpha: AppOpacity.overlay);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? accent.withValues(alpha: isDark ? 0.12 : 0.08)
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isHighlighted ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isRecent ? Icons.history_rounded : Icons.search_rounded,
                size: 18,
                color: isHighlighted ? accent : muted,
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.input.copyWith(
                    color:
                        isHighlighted
                            ? foreground
                            : foreground.withValues(alpha: isDark ? 0.88 : 0.9),
                    fontWeight:
                        isHighlighted
                            ? AppTypography.semiBold
                            : AppTypography.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.north_west_rounded,
                size: 14,
                color:
                    isHighlighted
                        ? accent
                        : muted.withValues(alpha: AppOpacity.medium),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HomeSearchSuggestionsState>(
      homeSearchSuggestionsProvider,
      (_, __) => _suggestionsOverlay?.markNeedsBuild(),
    );
    ref.listen<AsyncValue<List<String>>>(
      recentSearchesProvider,
      (_, __) => _suggestionsOverlay?.markNeedsBuild(),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final primaryCta = isDark ? AppColors.accentHighlight : AppColors.brand;
    final primaryCtaHover = isDark ? AppColors.brandLight : AppColors.brandDark;
    final primaryCtaDisabled = AppColors.brand.withValues(alpha: 0.12);
    // Nocturne ghost palette
    final ghostColor = AppColors.darkMuted;
    final metadataColor = AppColors.darkMetaText;
    final iconColor = isDark ? metadataColor : cs.onSurfaceVariant;
    final iconHoverBg =
        isDark ? AppColors.homeDarkCardHover : cs.surfaceContainerHighest;
    final neutralBorder = _neutralCommandBorder(isDark);

    return ClipRect(
      child: BackdropFilter(
        filter:
            isDark
                ? ImageFilter.blur(sigmaX: 24, sigmaY: 24)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        // AnimatedBuilder drives header border + TextField glow during extraction
        child: AnimatedBuilder(
          animation: _extractGlowAnimation,
          builder: (context, _) {
            final glow =
                widget.isExtracting ? _extractGlowAnimation.value : 0.0;
            return Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.mdLg,
                AppSpacing.md,
                AppSpacing.mdLg,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.homeDarkCardBg : Colors.white,
                borderRadius: BorderRadius.circular(
                  BrandConfig.current.cardRadius,
                ),
                border: Border.all(
                  color:
                      widget.isExtracting
                          ? AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.medium + glow * 0.2,
                          )
                          : (isDark
                              ? AppColors.homeDarkBorderSubtle
                              : Colors.black.withValues(alpha: 0.14)),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.04),
                    blurRadius: isDark ? 22 : 12,
                    offset: Offset(0, isDark ? 10 : 2),
                    spreadRadius: isDark ? -16 : 0,
                  ),
                ],
              ),
              child: Form(
                key: widget.formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.smMd),
                      child: Text(
                        AppLocalizations.homeSectionLinkOrKeyword,
                        style: AppTypography.fileName.copyWith(
                          fontSize: 15,
                          color:
                              isDark ? AppColors.darkLightText : cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    LayoutBuilder(
                      builder:
                          (context, constraints) => _buildResponsiveCommandBar(
                            constraints: constraints,
                            isDark: isDark,
                            cs: cs,
                            ghostColor: ghostColor,
                            metadataColor: metadataColor,
                            iconColor: iconColor,
                            iconHoverBg: iconHoverBg,
                            neutralBorder: neutralBorder,
                            glow: glow,
                            primaryCta: primaryCta,
                            primaryCtaHover: primaryCtaHover,
                            primaryCtaDisabled: primaryCtaDisabled,
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
