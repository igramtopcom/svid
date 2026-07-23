import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/browser_bookmark.dart';
import '../providers/browser_tab_providers.dart';
import '../providers/content_filter_providers.dart';

// ── Bookmark-card visual tokens ──
// A softer, larger corner than the brand's 12px card radius so the tiles read
// as friendly feature cards; the badge echoes it one step tighter.
const double _kTileRadius = 16;
const double _kBadgeRadius = 12;
const double _kBadgeSize = 42;

// Layered, slate-tinted elevation (matching AppShadow's palette) so cards lift
// off the page with a soft, diffuse edge rather than a hard grey line. The
// resting level already gives clear separation; hover deepens and spreads it.
const List<BoxShadow> _kCardShadowRest = [
  BoxShadow(color: Color(0x0D0F172A), offset: Offset(0, 1), blurRadius: 3),
  BoxShadow(
    color: Color(0x140F172A),
    offset: Offset(0, 6),
    blurRadius: 16,
    spreadRadius: -6,
  ),
];
const List<BoxShadow> _kCardShadowHover = [
  BoxShadow(color: Color(0x140F172A), offset: Offset(0, 2), blurRadius: 6),
  BoxShadow(
    color: Color(0x240F172A),
    offset: Offset(0, 14),
    blurRadius: 28,
    spreadRadius: -8,
  ),
];

/// Clean browser start page: a prominent URL/search bar + an editable grid of
/// bookmarks (seeded with popular platforms). No download stats or visited-site
/// clutter — just "type a URL / search" and "click a saved site".
class NewTabPage extends ConsumerWidget {
  const NewTabPage({
    super.key,
    required this.onNavigate,
    required this.onSearch,
  });

  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final bookmarks =
        ref.watch(browserBookmarkStreamProvider).valueOrNull ??
        ref.read(browserBookmarkServiceProvider).bookmarks;

    final cardBg = AppColors.surface2(context);
    final textSecondary =
        isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurface.withValues(alpha: AppOpacity.secondary);

    return Container(
      color: AppColors.surface1(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                // Feature hero — what this tab is for.
                Text(
                  AppLocalizations.newTabBrowserTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.appBarTitle.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkLightText : cs.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                  child: Text(
                    AppLocalizations.newTabBrowserSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.compact.copyWith(
                      color: textSecondary,
                      letterSpacing: 0,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(
                  child: _MissionControlSearch(
                    onSearch: onSearch,
                    onNavigate: onNavigate,
                    cardBg: cardBg,
                    textSecondary: textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                // Bookmarks header + Add
                Row(
                  children: [
                    _SectionHeader(
                      label: AppLocalizations.newTabBookmarks,
                      icon: Icons.bookmark_rounded,
                      textColor: isDark ? Colors.white : Colors.black,
                    ),
                    const Spacer(),
                    _AddButton(onTap: () => _showAddBookmarkDialog(context, ref)),
                  ],
                ),
                const SizedBox(height: AppSpacing.smMd),
                _BookmarkGrid(
                  bookmarks: bookmarks,
                  onNavigate: onNavigate,
                  onRemove:
                      (id) =>
                          ref.read(browserBookmarkServiceProvider).remove(id),
                  onAdd: () => _showAddBookmarkDialog(context, ref),
                  cardBg: cardBg,
                  textSecondary: textSecondary,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddBookmarkDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _AddBookmarkDialog(),
    );
    if (url == null) return;
    var normalized = url.trim();
    if (normalized.isEmpty) return;
    if (!normalized.contains('://')) normalized = 'https://$normalized';
    final host = Uri.tryParse(normalized)?.host ?? normalized;
    final title = (host.startsWith('www.') ? host.substring(4) : host);
    ref
        .read(browserBookmarkServiceProvider)
        .add(normalized, title.isEmpty ? normalized : title);
  }

  static String detectPlatform(String host) {
    final h = host.toLowerCase();
    if (h.contains('youtube') || h.contains('youtu.be')) return 'youtube';
    if (h.contains('facebook') || h.contains('fb.com')) return 'facebook';
    if (h.contains('instagram')) return 'instagram';
    if (h.contains('tiktok')) return 'tiktok';
    if (h.contains('twitter') || h == 'x.com') return 'x';
    if (h.contains('reddit')) return 'reddit';
    if (h.contains('pinterest')) return 'pinterest';
    if (h.contains('vimeo')) return 'vimeo';
    if (h.contains('soundcloud')) return 'soundcloud';
    if (h.contains('twitch')) return 'twitch';
    if (h.contains('dailymotion')) return 'dailymotion';
    if (h.contains('bilibili')) return 'bilibili';
    return '';
  }
}

// ── Bookmark grid ──

class _BookmarkGrid extends StatelessWidget {
  const _BookmarkGrid({
    required this.bookmarks,
    required this.onNavigate,
    required this.onRemove,
    required this.onAdd,
    required this.cardBg,
    required this.textSecondary,
  });

  final List<BrowserBookmark> bookmarks;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;
  final Color cardBg;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    // Fixed-size tiles (max-extent) so they stay compact and uniform no matter
    // how wide the browser pane is, instead of stretching into tall cards.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Don't clip the hover-lift shadow at the grid's edges.
      clipBehavior: Clip.none,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.0,
      ),
      itemCount: bookmarks.length + 1,
      itemBuilder: (context, index) {
        if (index == bookmarks.length) {
          return _AddBookmarkTile(onTap: onAdd);
        }
        final bm = bookmarks[index];
        return _BookmarkTile(
          bookmark: bm,
          onTap: () => onNavigate(bm.url),
          onRemove: () => onRemove(bm.id),
          cardBg: cardBg,
          textSecondary: textSecondary,
        );
      },
    );
  }
}

class _BookmarkTile extends StatefulWidget {
  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
    required this.onRemove,
    required this.cardBg,
    required this.textSecondary,
  });

  final BrowserBookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final Color cardBg;
  final Color textSecondary;

  @override
  State<_BookmarkTile> createState() => _BookmarkTileState();
}

class _BookmarkTileState extends State<_BookmarkTile> {
  bool _hovered = false;

  String get _host {
    final h = Uri.tryParse(widget.bookmark.url)?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  String get _initial {
    final t = widget.bookmark.title.trim();
    if (t.isNotEmpty) return t[0].toUpperCase();
    final h = _host;
    return h.isNotEmpty ? h[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final platform = NewTabPage.detectPlatform(_host);
    final hasIcon =
        platform.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platform);
    final color =
        hasIcon
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : AppColors.accentHighlight;
    final title =
        widget.bookmark.title.isNotEmpty ? widget.bookmark.title : _host;

    // Uniform neutral badge for EVERY tile (icon/letter carries the colour) —
    // avoids the previous look where each tile's badge took the platform tint
    // and some read as grey, some pink. Uses the page's surface colour so it
    // reads as a soft inset "chip" on the white card (adds internal contrast).
    final badgeBg = isDark ? AppColors.homeDarkAppBg : AppColors.surface1(context);

    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          // Soft upward lift on hover.
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(_kTileRadius),
            border: Border.all(
              color:
                  _hovered
                      ? AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.secondary,
                      )
                      : (isDark
                          ? AppColors.homeDarkBorderStrong
                          : cs.outline.withValues(alpha: 0.4)),
              width: _hovered ? 1.4 : 1,
            ),
            // Layered soft elevation; deepens on hover. (Dark mode leans on the
            // border — shadows read poorly on a dark surface.)
            boxShadow:
                isDark
                    ? null
                    : (_hovered ? _kCardShadowHover : _kCardShadowRest),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _kBadgeSize,
                      height: _kBadgeSize,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(_kBadgeRadius),
                      ),
                      child: Center(
                        child:
                            hasIcon
                                ? PlatformIcon(platform: platform, size: 24)
                                : Text(
                                  _initial,
                                  style: AppTypography.appBarTitle.copyWith(
                                    fontSize: 19,
                                    color: color,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.smMd),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.compact.copyWith(
                        fontSize: 14,
                        color:
                            _hovered
                                ? (isDark ? Colors.white : cs.onSurface)
                                : widget.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              // Remove — a clean, self-contained corner button on hover.
              if (_hovered)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: AppLocalizations.newTabRemoveBookmark,
                    child: GestureDetector(
                      onTap: widget.onRemove,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          // Soft dark disc so it reads clearly on the white
                          // card (a white button was invisible), with a light
                          // ring for separation.
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: AppOpacity.secondary,
                            ),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 4),
                          ],
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddBookmarkTile extends StatefulWidget {
  const _AddBookmarkTile({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddBookmarkTile> createState() => _AddBookmarkTileState();
}

class _AddBookmarkTileState extends State<_AddBookmarkTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.accentHighlight;
    final base = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: AppOpacity.medium);
    final badgeBg = isDark ? AppColors.homeDarkAppBg : AppColors.surface1(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(_kTileRadius),
            border: Border.all(
              color: _hovered ? accent.withValues(alpha: 0.5) : base,
              width: _hovered ? 1.4 : 1,
            ),
            boxShadow:
                isDark
                    ? null
                    : (_hovered ? _kCardShadowHover : _kCardShadowRest),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _kBadgeSize,
                  height: _kBadgeSize,
                  decoration: BoxDecoration(
                    color: _hovered ? accent.withValues(alpha: AppOpacity.hover) : badgeBg,
                    borderRadius: BorderRadius.circular(_kBadgeRadius),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 23,
                    color: _hovered ? accent : base,
                  ),
                ),
                const SizedBox(height: AppSpacing.smMd),
                Text(
                  AppLocalizations.newTabAddBookmark,
                  style: AppTypography.compact.copyWith(
                    fontSize: 14,
                    color: _hovered ? accent : base,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.add_rounded, size: 18, color: accent),
      label: Text(AppLocalizations.newTabAddBookmark),
      style: TextButton.styleFrom(
        foregroundColor: accent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
    );
  }
}

// ── Add-bookmark dialog ──

class _AddBookmarkDialog extends StatefulWidget {
  const _AddBookmarkDialog();

  @override
  State<_AddBookmarkDialog> createState() => _AddBookmarkDialogState();
}

class _AddBookmarkDialogState extends State<_AddBookmarkDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.homeDarkCardBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      title: Text(AppLocalizations.newTabAddBookmarkTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: AppLocalizations.newTabAddBookmarkHint,
          prefixIcon: const Icon(Icons.link_rounded, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
          ),
          child: Text(AppLocalizations.newTabAddBookmark),
        ),
      ],
    );
  }
}

// ── Mission Control Search Input ──

class _MissionControlSearch extends ConsumerStatefulWidget {
  const _MissionControlSearch({
    required this.onSearch,
    required this.onNavigate,
    required this.cardBg,
    required this.textSecondary,
  });

  final ValueChanged<String> onSearch;
  final ValueChanged<String> onNavigate;
  final Color cardBg;
  final Color textSecondary;

  @override
  ConsumerState<_MissionControlSearch> createState() =>
      _MissionControlSearchState();
}

class _MissionControlSearchState extends ConsumerState<_MissionControlSearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(selectedSearchEngineProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow:
              _isFocused
                  ? [
                    BoxShadow(
                      color: AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.quarter,
                      ),
                      blurRadius: 25,
                      spreadRadius: -5,
                    ),
                  ]
                  : [],
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          style: AppTypography.appBarTitle.copyWith(
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: AppLocalizations.newTabSearchPlaceholder(engine.label),
            hintStyle: AppTypography.appBarTitle.copyWith(
              fontWeight: FontWeight.w400,
              color: widget.textSecondary.withValues(alpha: AppOpacity.overlay),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Icon(
                Icons.search_rounded,
                color:
                    _isFocused
                        ? AppColors.accentHighlight
                        : widget.textSecondary,
                size: 22,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 46,
              minHeight: 0,
            ),
            suffixIcon: Container(
              margin: const EdgeInsets.all(AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smMd,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight.withValues(
                  alpha: AppOpacity.pressed,
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                engine.label,
                style: AppTypography.compact.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentHighlight,
                  letterSpacing: 0,
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdLg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : Theme.of(context).colorScheme.outline.withValues(
                          alpha: AppOpacity.medium,
                        ),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : Theme.of(context).colorScheme.outline.withValues(
                          alpha: AppOpacity.medium,
                        ),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkInputBorder
                        : AppColors.accentHighlight,
                width: 1,
              ),
            ),
            filled: true,
            fillColor: widget.cardBg,
          ),
          onSubmitted: (query) {
            final trimmed = query.trim();
            if (trimmed.isEmpty) return;
            if (trimmed.contains('.') && !trimmed.contains(' ')) {
              widget.onNavigate(trimmed);
            } else {
              widget.onSearch(trimmed);
            }
          },
        ),
      ),
    );
  }
}

// ── Section Header ──

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.textColor,
  });

  final String label;
  final IconData icon;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.sectionHeader.copyWith(color: textColor),
        ),
      ],
    );
  }
}
