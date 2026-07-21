import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/brand_config.dart';
import '../../constants/app_assets.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../binary_downloader.dart';
import '../binary_manager.dart';
import '../binary_providers.dart';
import '../binary_type.dart';

/// Nocturne Cinematic setup screen — shown on first launch while
/// downloading yt-dlp, ffmpeg, and gallery-dl.
///
/// Design ref: Stitch `348c7397` (dark) / `a4da878d` (light)
/// Spec: docs/design-specs/first-time-setup.md
class BinarySetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onSetupComplete;

  const BinarySetupScreen({
    super.key,
    required this.onSetupComplete,
  });

  @override
  ConsumerState<BinarySetupScreen> createState() => _BinarySetupScreenState();
}

class _BinarySetupScreenState extends ConsumerState<BinarySetupScreen>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  bool _isComplete = false;
  // Optional binaries (e.g. gallery-dl) whose mirror chain failed during
  // setup. App is still usable — yt-dlp + ffmpeg cover video extraction —
  // but image/carousel features (Instagram, Pinterest carousels) won't
  // work until the user runs Settings → Re-download tools or upstream
  // recovers. We surface this BEFORE auto-advancing onSetupComplete so
  // users aren't blindsided by a feature being silently broken.
  List<BinaryType> _skippedOptional = const [];
  String? _error;
  bool _showDetails = false;

  // Track progress per binary
  final Map<BinaryType, _BinaryDownloadState> _binaryStates = {};

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _progressFade;
  late final Animation<Offset> _logoSlide;

  @override
  void initState() {
    super.initState();

    // Initialize binary states (only for platform-required binaries)
    for (final type in BinaryManager.requiredBinaries) {
      _binaryStates[type] = _BinaryDownloadState();
    }

    // Entrance animation: staggered fade+slide
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _textFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
    );

    _progressFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    _entranceController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndDownload();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  // ==================== DOWNLOAD LOGIC (preserved) ====================

  Future<void> _initializeAndDownload() async {
    final manager = ref.read(binaryManagerProvider);
    await manager.initialize();

    for (final type in BinaryType.values) {
      final isAvailable = await manager.isAvailable(type);
      if (isAvailable && mounted) {
        setState(() {
          _binaryStates[type]!.status = _BinaryStatus.completed;
        });
      }
    }

    await _startDownload();
  }

  Future<void> _startDownload() async {
    if (_isDownloading) return;

    final manager = ref.read(binaryManagerProvider);
    final missing = await manager.getMissingBinaries();

    if (missing.isEmpty) {
      if (mounted) {
        setState(() => _isComplete = true);
        await Future.delayed(const Duration(milliseconds: 500));
        widget.onSetupComplete();
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _error = null;
      _showDetails = false;
      for (final type in missing) {
        _binaryStates[type]!.status = _BinaryStatus.starting;
      }
    });

    try {
      await for (final progress in manager.downloadAllMissing()) {
        if (!mounted) return;

        setState(() {
          if (progress.currentBinary != null &&
              progress.currentProgress != null) {
            final state = _binaryStates[progress.currentBinary]!;
            state.status = _BinaryStatusExt.fromDownloadStatus(
                progress.currentProgress!.status);
            state.progress = progress.currentProgress!.progress;
            state.downloadedBytes = progress.currentProgress!.downloadedBytes;
            state.totalBytes = progress.currentProgress!.totalBytes;
          }

          if (progress.status == BinaryManagerStatus.completed) {
            _isComplete = true;
            _isDownloading = false;
            _skippedOptional = progress.skippedOptional;
          } else if (progress.status == BinaryManagerStatus.error) {
            _error = progress.error ?? 'Download failed';
            _isDownloading = false;
            _showDetails = true; // Auto-expand on error
          }
        });
      }

      if (_isComplete && mounted) {
        // Hold the screen long enough for the user to read the
        // skipped-optional warning when present. Without this delay, a
        // user whose gallery-dl install failed sees the screen flash
        // green and disappear, then later wonders why image download
        // is broken.
        final delay = _skippedOptional.isNotEmpty
            ? const Duration(seconds: 4)
            : const Duration(milliseconds: 500);
        await Future.delayed(delay);
        if (mounted) widget.onSetupComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isDownloading = false;
          _showDetails = true;
        });
      }
    }
  }

  // ==================== COMPUTED STATE ====================

  int get _completedCount =>
      _binaryStates.values
          .where((s) => s.status == _BinaryStatus.completed)
          .length;

  int get _totalCount => BinaryManager.requiredBinaries.length;

  double get _overallProgress {
    if (_isComplete) return 1.0;
    final completed = _completedCount;
    final currentBinaryProgress = _currentDownloadingState?.progress ?? 0.0;
    return (completed + currentBinaryProgress) / _totalCount;
  }

  _BinaryDownloadState? get _currentDownloadingState {
    for (final type in BinaryManager.requiredBinaries) {
      final state = _binaryStates[type]!;
      if (state.status == _BinaryStatus.downloading ||
          state.status == _BinaryStatus.extracting ||
          state.status == _BinaryStatus.starting) {
        return state;
      }
    }
    return null;
  }

  BinaryType? get _currentDownloadingType {
    for (final type in BinaryManager.requiredBinaries) {
      final state = _binaryStates[type]!;
      if (state.status == _BinaryStatus.downloading ||
          state.status == _BinaryStatus.extracting ||
          state.status == _BinaryStatus.starting) {
        return type;
      }
    }
    return null;
  }

  String get _stepLabel {
    if (_isComplete) return 'Ready!';
    final current = _currentDownloadingType;
    if (current == null) return 'Checking components...';
    final step = _completedCount + 1;
    return '${_friendlyBinaryName(current)} · $step of $_totalCount';
  }

  String get _subtitle {
    if (_error != null) return 'Something went wrong';
    if (_isComplete) return "You're all set!";
    return 'Preparing your experience...';
  }

  String _friendlyBinaryName(BinaryType type) {
    return switch (type) {
      BinaryType.ytDlp => 'Setting up video engine',
      BinaryType.ffmpeg => 'Setting up media tools',
      BinaryType.galleryDl => 'Setting up image engine',
      BinaryType.deno => 'Setting up YouTube engine runtime',
    };
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // Layer 0: Background effects
          _buildBackgroundEffects(isDark),

          // Layer 1: Main content
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    SlideTransition(
                      position: _logoSlide,
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: _buildLogo(isDark),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Title
                    FadeTransition(
                      opacity: _textFade,
                      child: Text(
                        'Welcome to ${AppConstants.appName}',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // Subtitle (animated crossfade)
                    FadeTransition(
                      opacity: _textFade,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _subtitle,
                          key: ValueKey(_subtitle),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.muted(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Progress bar + step counter
                    FadeTransition(
                      opacity: _progressFade,
                      child: _buildProgress(isDark),
                    ),

                    // Expandable detail section
                    _buildDetailSection(theme, colorScheme),

                    const SizedBox(height: AppSpacing.lg),

                    // Error state
                    if (_error != null) _buildError(theme, colorScheme),

                    // Skipped optional binaries — non-fatal warning.
                    // Rendered between progress and success so the user
                    // sees the degradation BEFORE the screen advances.
                    if (_skippedOptional.isNotEmpty && _error == null)
                      _buildSkippedOptionalWarning(theme, colorScheme),

                    // Success state
                    if (_isComplete && _error == null) _buildSuccess(theme),
                  ],
                ),
              ),
            ),
          ),

          // Layer 2: Footer
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _progressFade,
              child: Center(
                child: Text(
                  'THIS ONLY HAPPENS ONCE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDark
                        ? AppColors.darkMuted
                        : AppColors.lightBorder,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== UI COMPONENTS ====================

  Widget _buildBackgroundEffects(bool isDark) {
    if (isDark) {
      return Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.7,
              colors: [
                AppColors.darkBase,
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
        ),
      );
    }

    // Light mode: subtle decorative blur circles
    return Stack(
      children: [
        Positioned(
          bottom: -128,
          right: -128,
          child: Container(
            width: 384,
            height: 384,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentHighlight.withValues(alpha: AppOpacity.divider),
            ),
          ),
        ),
        Positioned(
          top: -128,
          left: -128,
          child: Container(
            width: 384,
            height: 384,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brand.withValues(alpha: AppOpacity.divider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: isDark ? AppOpacity.medium : AppOpacity.quarter),
            blurRadius: isDark ? 30 : 20,
            spreadRadius: isDark ? 4 : 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Image.asset(
          AppAssets.logo,
          width: 88,
          height: 88,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildProgress(bool isDark) {
    return SizedBox(
      width: 300,
      child: Column(
        children: [
          // Progress track
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface3 : AppColors.lightSurface3,
              borderRadius: BorderRadius.circular(999),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      width: constraints.maxWidth * _overallProgress.clamp(0.0, 1.0),
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.brand, AppColors.accentHighlight],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          // Step counter
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _stepLabel,
              key: ValueKey(_stepLabel),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.muted(context),
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.md),
        // Toggle link
        GestureDetector(
          onTap: () => setState(() => _showDetails = !_showDetails),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              _showDetails ? 'Hide details' : 'Show details',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // Detail list (animated)
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.smMd),
            child: Column(
              children: BinaryManager.requiredBinaries.map((type) {
                final state = _binaryStates[type]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      _buildDetailStatusIcon(state.status, colorScheme),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          type.displayName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: AppOpacity.strong),
                          ),
                        ),
                      ),
                      if (state.status == _BinaryStatus.downloading)
                        Text(
                          '${state.percentage}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (state.status == _BinaryStatus.completed)
                        Icon(Icons.check, size: 14,
                            color: AppColors.success(context)),
                      if (state.status == _BinaryStatus.error)
                        Icon(Icons.close, size: 14, color: colorScheme.error),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          crossFadeState: _showDetails
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildDetailStatusIcon(_BinaryStatus status, ColorScheme colorScheme) {
    const size = 14.0;
    return switch (status) {
      _BinaryStatus.pending => Icon(Icons.circle_outlined,
          size: size, color: colorScheme.outline),
      _BinaryStatus.starting || _BinaryStatus.downloading ||
      _BinaryStatus.extracting =>
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colorScheme.primary,
          ),
        ),
      _BinaryStatus.completed => Icon(Icons.check_circle,
          size: size, color: AppColors.success(context)),
      _BinaryStatus.error => Icon(Icons.error,
          size: size, color: colorScheme.error),
    };
  }

  Widget _buildError(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 20, color: colorScheme.onErrorContainer),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: Text(
                      _friendlyErrorMessage(_error!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              if (_friendlyErrorMessage(_error!) != _error!) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer.withValues(alpha: AppOpacity.strong),
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.smMd),
        FilledButton.icon(
          onPressed: _startDownload,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  /// Non-fatal warning when an `optional` binary (currently only
  /// gallery-dl) failed its mirror chain. App still proceeds — yt-dlp
  /// + ffmpeg cover video extraction — but image/carousel features
  /// will be unavailable until the user retries from settings.
  Widget _buildSkippedOptionalWarning(ThemeData theme, ColorScheme colorScheme) {
    final names = _skippedOptional
        .map((t) => t.displayName)
        .join(', ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Optional tool unavailable: $names',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Video and audio downloads work normally. Image / carousel '
                  'downloads (Instagram, Pinterest, etc.) will be skipped until '
                  'this tool is available — retry from Settings → Engine.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onTertiaryContainer
                        .withValues(alpha: AppOpacity.strong),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success(context).withValues(alpha: AppOpacity.pressed),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.success(context), size: 22),
          const SizedBox(width: AppSpacing.smMd),
          Text(
            'Setup complete!',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.success(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPERS (preserved) ====================

  String _friendlyErrorMessage(String raw) {
    final lower = raw.toLowerCase();

    if (lower.contains('certificate_verify_failed') ||
        lower.contains('handshakeexception') ||
        lower.contains('bad certificate') ||
        lower.contains('tlsexception') ||
        lower.contains('ssl')) {
      return 'SSL certificate error. Try:\n'
          '1. Disable SSL scanning in your antivirus\n'
          '2. Disconnect VPN and retry\n'
          '3. Check that your system date/time is correct';
    }

    if (lower.contains('socketexception') ||
        lower.contains('no internet') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup')) {
      return 'No internet connection. Check your network and try again.';
    }

    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Server is slow or unreachable. Please try again.';
    }

    if (lower.contains('exec format error') ||
        lower.contains('bad cpu type')) {
      return 'This binary is not compatible with your processor.\n'
          'Your Mac may need a different version (Intel vs Apple Silicon).';
    }

    if (lower.contains('cannot execute') ||
        lower.contains('access is denied') ||
        lower.contains('operation not permitted') ||
        lower.contains('is not recognized') ||
        lower.contains('quarantine') ||
        lower.contains('antivirus')) {
      return 'Binary blocked by antivirus or system security.\n'
          'Add an exception for the ${BrandConfig.current.appName} bin folder in your antivirus settings.';
    }

    if (lower.contains('http') &&
        (lower.contains('404') || lower.contains('not found'))) {
      return 'Download URL not found. The file may have been moved. Please try again later.';
    }

    return raw;
  }

}

/// Internal state for tracking individual binary download
class _BinaryDownloadState {
  _BinaryStatus status = _BinaryStatus.pending;
  double progress = 0;
  int downloadedBytes = 0;
  int totalBytes = 0;

  int get percentage => (progress * 100).round();
}

/// Extended status that includes pending state
enum _BinaryStatus {
  pending,
  starting,
  downloading,
  extracting,
  completed,
  error,
}

extension _BinaryStatusExt on _BinaryStatus {
  static _BinaryStatus fromDownloadStatus(BinaryDownloadStatus status) {
    return switch (status) {
      BinaryDownloadStatus.starting => _BinaryStatus.starting,
      BinaryDownloadStatus.downloading => _BinaryStatus.downloading,
      BinaryDownloadStatus.extracting => _BinaryStatus.extracting,
      BinaryDownloadStatus.completed => _BinaryStatus.completed,
      BinaryDownloadStatus.error => _BinaryStatus.error,
    };
  }
}
