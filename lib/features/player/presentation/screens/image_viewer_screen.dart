import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';

/// Image Viewer Screen — "The Private Gallery"
///
/// Single image mode: pass [download] only.
/// Carousel mode: pass [download] + [carouselDownloads] (list of sibling images).
///
/// Features:
/// - Auto-hiding chrome (top bar, controls, filmstrip fade after 3s)
/// - Carousel thumbnail filmstrip for direct navigation
/// - Zoom/pan with InteractiveViewer + keyboard shortcuts
/// - Double-tap to zoom 2x / reset
/// - Glassmorphic floating controls
class ImageViewerScreen extends ConsumerStatefulWidget {
  final DownloadEntity download;
  final List<DownloadEntity>? carouselDownloads;

  const ImageViewerScreen({
    super.key,
    required this.download,
    this.carouselDownloads,
  });

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen> {
  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _thumbScrollController = ScrollController();
  TapDownDetails? _doubleTapDetails;
  late final PageController _pageController;
  int _currentIndex = 0;

  // Auto-hiding chrome
  bool _chromeVisible = true;
  Timer? _hideTimer;
  static const _chromeTimeout = Duration(seconds: 3);
  static const _chromeFadeDuration = Duration(milliseconds: 300);

  List<DownloadEntity> get _allImages =>
      widget.carouselDownloads ?? [widget.download];

  bool get _isCarousel => _allImages.length > 1;

  DownloadEntity get _currentDownload => _allImages[_currentIndex];

  @override
  void initState() {
    super.initState();
    if (widget.carouselDownloads != null) {
      _currentIndex = widget.carouselDownloads!
          .indexWhere((d) => d.id == widget.download.id)
          .clamp(0, widget.carouselDownloads!.length - 1);
    }
    _pageController = PageController(initialPage: _currentIndex);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _transformationController.dispose();
    _pageController.dispose();
    _thumbScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Auto-hide chrome ──────────────────────────────────────────

  void _showChrome() {
    if (!_chromeVisible && mounted) {
      setState(() => _chromeVisible = true);
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_chromeTimeout, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  // ─── Keyboard shortcuts ────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    _showChrome();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (_isCarousel && _currentIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.arrowRight:
        if (_isCarousel && _currentIndex < _allImages.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.equal || LogicalKeyboardKey.add:
        _zoomIn();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
        _zoomOut();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit0:
        _transformationController.value = Matrix4.identity();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Zoom ──────────────────────────────────────────────────────

  void _zoomIn() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (scale + 0.5).clamp(0.1, 10.0);
    _transformationController.value = Matrix4.identity()
      ..scale(newScale, newScale, 1.0);
  }

  void _zoomOut() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (scale - 0.5).clamp(0.1, 10.0);
    _transformationController.value = Matrix4.identity()
      ..scale(newScale, newScale, 1.0);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx, -position.dy, 0.0)
        ..scale(2.0, 2.0, 1.0);
    }
  }

  // ─── Filmstrip scroll ──────────────────────────────────────────

  void _scrollThumbToIndex(int index) {
    if (!_thumbScrollController.hasClients) return;
    // Each thumb = 56px wide + 8px gap
    final targetOffset = (index * 64.0) -
        (MediaQuery.of(context).size.width / 2) +
        32;
    _thumbScrollController.animateTo(
      targetOffset.clamp(
        0.0,
        _thumbScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : cs.surface,
        body: MouseRegion(
          onHover: (_) => _showChrome(),
          child: GestureDetector(
            onTap: () {
              if (_chromeVisible) {
                _hideTimer?.cancel();
                setState(() => _chromeVisible = false);
              } else {
                _showChrome();
              }
            },
            child: Stack(
              children: [
                // Subtle ambient glow — radial gradient, not solid blob
                if (isDark)
                  Center(
                    child: Container(
                      width: 900,
                      height: 600,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.brand.withValues(alpha: AppOpacity.divider),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                    ),
                  ),

                // Image viewer (full area — behind all chrome)
                Positioned.fill(
                  child: _isCarousel
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: _allImages.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentIndex = index;
                              _transformationController.value =
                                  Matrix4.identity();
                            });
                            _scrollThumbToIndex(index);
                            _showChrome();
                          },
                          itemBuilder: (context, index) =>
                              _buildImagePage(_allImages[index]),
                        )
                      : _buildImagePage(_allImages.first),
                ),

                // ─── Auto-hiding chrome layer ───

                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 1.0 : 0.0,
                    duration: _chromeFadeDuration,
                    child: IgnorePointer(
                      ignoring: !_chromeVisible,
                      child: _buildTopBar(cs, isDark),
                    ),
                  ),
                ),

                // Bottom zone: controls + filmstrip + keyboard hints
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 1.0 : 0.0,
                    duration: _chromeFadeDuration,
                    child: IgnorePointer(
                      ignoring: !_chromeVisible,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Floating controls pill
                          _buildFloatingControls(cs, isDark),
                          // Thumbnail filmstrip (carousel only)
                          if (_isCarousel) ...[
                            const SizedBox(height: AppSpacing.smMd),
                            _buildFilmstrip(cs, isDark),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          // Keyboard hints
                          _buildKeyboardHints(cs),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Top Bar ───────────────────────────────────────────────────

  Widget _buildTopBar(ColorScheme cs, bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 52,
          padding: EdgeInsets.only(
            left: Platform.isMacOS ? 78 : AppSpacing.sm,
            right: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
                      AppColors.darkBg.withValues(alpha: 0.0),
                    ]
                  : [
                      Colors.white.withValues(alpha: AppOpacity.nearOpaque),
                      Colors.white.withValues(alpha: 0.0),
                    ],
            ),
          ),
          child: Row(
            children: [
              // Back arrow
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: AppOpacity.strong),
                ),
                tooltip: AppLocalizations.playerBack,
              ),

              // Filename — center
              Expanded(
                child: Text(
                  _currentDownload.filename,
                  style: AppTypography.metadata.copyWith(
                    color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Reset zoom
              IconButton(
                onPressed: () {
                  _transformationController.value = Matrix4.identity();
                },
                icon: Icon(
                  Icons.zoom_out_map,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                ),
                tooltip: AppLocalizations.playerResetZoom,
              ),

              // Info
              IconButton(
                onPressed: _showImageInfo,
                icon: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                ),
                tooltip: AppLocalizations.playerImageInfo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Floating Controls Pill ────────────────────────────────────

  Widget _buildFloatingControls(ColorScheme cs, bool isDark) {
    final iconColor = cs.onSurface.withValues(alpha: AppOpacity.overlay);
    final disabledColor = cs.onSurface.withValues(alpha: AppOpacity.subtle);

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: AppOpacity.hover)
                  : Colors.black.withValues(alpha: AppOpacity.divider),
              borderRadius: BorderRadius.circular(9999),
              // Stitch: subtle wine-tinted ambient shadow on pill
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: BrandConfig.current.colors.gradientTail.withValues(alpha: AppOpacity.divider),
                        blurRadius: 48,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous
                if (_isCarousel)
                  _pillButton(
                    icon: Icons.chevron_left,
                    color: _currentIndex > 0 ? iconColor : disabledColor,
                    onTap: _currentIndex > 0
                        ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                        : null,
                    tooltip: AppLocalizations.playerPrevious,
                  ),

                // Zoom out
                _pillButton(
                  icon: Icons.remove,
                  color: iconColor,
                  onTap: _zoomOut,
                  tooltip: AppLocalizations.playerZoomOut,
                ),

                // Counter or fit-to-screen
                if (_isCarousel)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${_allImages.length}',
                      style: AppTypography.metadata.copyWith(
                        color: cs.onSurface,
                        letterSpacing: 0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                else
                  _pillButton(
                    icon: Icons.fit_screen_outlined,
                    color: iconColor,
                    onTap: () {
                      _transformationController.value = Matrix4.identity();
                    },
                    tooltip: AppLocalizations.playerFitToScreen,
                  ),

                // Zoom in
                _pillButton(
                  icon: Icons.add,
                  color: iconColor,
                  onTap: _zoomIn,
                  tooltip: AppLocalizations.playerZoomIn,
                ),

                // Next
                if (_isCarousel)
                  _pillButton(
                    icon: Icons.chevron_right,
                    color: _currentIndex < _allImages.length - 1
                        ? iconColor
                        : disabledColor,
                    onTap: _currentIndex < _allImages.length - 1
                        ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            )
                        : null,
                    tooltip: AppLocalizations.playerNext,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      waitDuration: AppDurations.tooltipWaitDuration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9999),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.smMd),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }

  // ─── Thumbnail Filmstrip ───────────────────────────────────────

  Widget _buildFilmstrip(ColorScheme cs, bool isDark) {
    return SizedBox(
      height: 56,
      child: Center(
        child: ListView.separated(
          controller: _thumbScrollController,
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: _allImages.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
          final download = _allImages[index];
          final isActive = index == _currentIndex;
          final filePath = '${download.savePath}/${download.filename}';
          final file = File(filePath);

          return GestureDetector(
            onTap: () {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isActive ? 1.0 : 0.8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: isActive
                      ? Border.all(
                          color: AppColors.accentHighlight,
                          width: 2,
                        )
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isActive ? 2 : 4),
                  child: file.existsSync()
                      ? Image.file(
                          file,
                          fit: BoxFit.cover,
                          cacheWidth: 112, // 56 * 2 for retina
                          errorBuilder: (_, __, ___) => _thumbPlaceholder(cs),
                        )
                      : _thumbPlaceholder(cs),
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(ColorScheme cs) {
    return Container(
      color: AppColors.surface2(context),
      child: Icon(
        Icons.image_outlined,
        size: 20,
        color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
      ),
    );
  }

  // ─── Keyboard Hints ────────────────────────────────────────────

  Widget _buildKeyboardHints(ColorScheme cs) {
    return Text(
      _isCarousel
          ? '←→: NAVIGATE  •  +−: ZOOM  •  0: RESET  •  ESC: CLOSE'
          : '+−: ZOOM  •  0: RESET  •  DOUBLE-CLICK: 2×  •  ESC: CLOSE',
      textAlign: TextAlign.center,
      style: AppTypography.mini.copyWith(
        color: cs.onSurface.withValues(alpha: AppOpacity.subtle),
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
    );
  }

  // ─── Image Page ────────────────────────────────────────────────

  Widget _buildImagePage(DownloadEntity download) {
    final filePath = '${download.savePath}/${download.filename}';
    final file = File(filePath);

    if (!file.existsSync()) {
      return _buildErrorView(download.filename);
    }

    // Extra bottom padding in carousel mode to clear filmstrip + controls + hints
    final bottomChrome = _isCarousel ? 150.0 : 100.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.only(left: 40, right: 40, top: 52, bottom: bottomChrome),
        child: GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.1,
            maxScale: 10.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                // Stitch: ghost outline to separate image from void
                border: Border.all(
                  color: Colors.white.withValues(alpha: AppOpacity.divider),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildErrorView(download.filename);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Error View ────────────────────────────────────────────────

  Widget _buildErrorView([String? filename]) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 64,
            color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.playerImageLoadFailed,
            style: AppTypography.fileName.copyWith(
              fontWeight: FontWeight.w400,
              color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            filename ?? widget.download.filename,
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w300,
              color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Image Info Dialog ─────────────────────────────────────────

  void _showImageInfo() {
    final download = _currentDownload;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? AppColors.darkSurface2 : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.playerImageInformation,
                  style: AppTypography.fileName.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: AppSpacing.mdLg),
                _buildInfoRow(
                  cs,
                  AppLocalizations.playerInfoFilename,
                  download.filename,
                ),
                const SizedBox(height: AppSpacing.smMd),
                _buildInfoRow(
                  cs,
                  AppLocalizations.playerInfoSize,
                  FileUtils.formatBytes(download.totalBytes),
                ),
                const SizedBox(height: AppSpacing.smMd),
                _buildInfoRow(
                  cs,
                  AppLocalizations.playerInfoLocation,
                  download.savePath,
                ),
                const SizedBox(height: AppSpacing.smMd),
                _buildInfoRow(
                  cs,
                  AppLocalizations.playerInfoFormat,
                  download.fileExtension.toUpperCase(),
                ),
                const SizedBox(height: AppSpacing.smMd),
                _buildInfoRow(
                  cs,
                  AppLocalizations.playerInfoDownloaded,
                  Formatters.formatDate(download.createdAt),
                ),
                if (_isCarousel) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  _buildInfoRow(
                    cs,
                    'Image',
                    '${_currentIndex + 1} of ${_allImages.length}',
                  ),
                ],
                const SizedBox(height: AppSpacing.mdLg),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accentHighlight,
                    ),
                    child: Text(AppLocalizations.commonClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(ColorScheme cs, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: AppTypography.statusBadge.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.medium),
              letterSpacing: 0,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.statusBadge.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.nearOpaque),
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
