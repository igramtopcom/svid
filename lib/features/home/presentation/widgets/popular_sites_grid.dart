import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/core.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../browser/presentation/providers/browser_providers.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../../../core/auth/presentation/providers/auth_providers.dart';

/// Platform Ribbon — compact horizontal pills replacing 4×2 grid
/// Row 1: YouTube action buttons (Search, Playlist, Channel, Subscriptions)
/// Row 2: Platform navigation pills (YouTube, TikTok, Instagram, ...)
class PopularSitesGrid extends ConsumerWidget {
  final Function(String)? onPlatformTap;
  final Future<void> Function(List<String>)? onBatchDownload;

  const PopularSitesGrid({super.key, this.onPlatformTap, this.onBatchDownload});

  static const List<PlatformInfo> _platforms = [
    PlatformInfo(
      name: 'YouTube',
      url: 'www.youtube.com',
      svgPath: 'assets/icons/platforms/youtube.svg',
      color: Color(0xFFFF0000),
      loginUrl:
          'https://accounts.google.com/ServiceLogin?continue=https://www.youtube.com/',
    ),
    PlatformInfo(
      name: 'Facebook',
      url: 'www.facebook.com',
      svgPath: 'assets/icons/platforms/facebook.svg',
      color: Color(0xFF1877F2),
      loginUrl: 'https://www.facebook.com/login',
    ),
    PlatformInfo(
      name: 'Instagram',
      url: 'www.instagram.com',
      svgPath: 'assets/icons/platforms/instagram.svg',
      color: Color(0xFFE4405F),
      loginUrl: 'https://www.instagram.com/accounts/login',
    ),
    PlatformInfo(
      name: 'TikTok',
      url: 'www.tiktok.com',
      svgPath: 'assets/icons/platforms/tiktok.svg',
      color: Color(0xFF000000),
      loginUrl: 'https://www.tiktok.com/login',
    ),
    PlatformInfo(
      name: 'X',
      url: 'www.x.com',
      svgPath: 'assets/icons/platforms/x.svg',
      color: Color(0xFF000000),
      loginUrl: 'https://twitter.com/i/flow/login',
    ),
    PlatformInfo(
      name: 'Reddit',
      url: 'www.reddit.com',
      svgPath: 'assets/icons/platforms/reddit.svg',
      color: Color(0xFFFF4500),
      loginUrl: 'https://www.reddit.com/login',
    ),
    PlatformInfo(
      name: 'Pinterest',
      url: 'www.pinterest.com',
      svgPath: 'assets/icons/platforms/pinterest.svg',
      color: Color(0xFFE60023),
      loginUrl: 'https://www.pinterest.com/login',
    ),
    PlatformInfo(
      name: '',
      url: '',
      svgPath: 'assets/icons/platforms/other.svg',
      color: Color(0xFF757575), // lightMetaText — must be const for static list
      isOther: true,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Row 1 ("Tìm Kiếm Video / Duyệt Danh Sách Phát / Kênh") removed —
    // those flows now route through the smart input field's adaptive
    // submit (keyword → search sheet, channel URL → channel sheet,
    // playlist URL → playlist sheet) so the home shell reclaims
    // vertical space and the user has a single entry point.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            _platforms.map((platform) {
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _PlatformPill(platform: platform),
              );
            }).toList(),
      ),
    );
  }
}

/// Nocturne YouTube action chip — glass morphism with crimson accents
class _YouTubeActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _YouTubeActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_YouTubeActionButton> createState() => _YouTubeActionButtonState();
}

class _YouTubeActionButtonState extends State<_YouTubeActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
          decoration: BoxDecoration(
            color:
                isDark
                    ? (_isHovered
                        ? AppColors.homeDarkCardHover
                        : AppColors.homeDarkCardBg)
                    : (_isHovered
                        ? AppColors.lightSurface3
                        : AppColors.lightSurface2),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? (_isHovered
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.homeDarkBorderSubtle)
                      : cs.outlineVariant.withValues(alpha: AppOpacity.scrim),
              width: 0.5,
            ),
            boxShadow:
                isDark && _isHovered
                    ? [
                      BoxShadow(
                        color: AppColors.brand.withValues(
                          alpha: AppOpacity.subtle,
                        ),
                        blurRadius: 12,
                        spreadRadius: -3,
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: widget.color),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.label,
                style: AppTypography.metadata.copyWith(
                  fontWeight: _isHovered ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isDark
                          ? (_isHovered
                              ? AppColors.accentHighlight
                              : AppColors.homeDarkTextSecondary)
                          : cs.onSurface.withValues(alpha: AppOpacity.strong),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform navigation pill — glass morphism, opens browser on tap
class _PlatformPill extends ConsumerStatefulWidget {
  final PlatformInfo platform;

  const _PlatformPill({required this.platform});

  @override
  ConsumerState<_PlatformPill> createState() => _PlatformPillState();
}

class _PlatformPillState extends ConsumerState<_PlatformPill>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isLoggedIn = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _checkLoginStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    if (widget.platform.isOther) return;
    final getPlatformCookiesUseCase = ref.read(
      getPlatformCookiesUseCaseProvider,
    );
    final result = await getPlatformCookiesUseCase(
      widget.platform.name.toLowerCase(),
    );
    if (result.isFailure) return;
    if (mounted && result.isSuccess && result.dataOrNull != null) {
      setState(() => _isLoggedIn = true);
    }
  }

  Future<void> _handleLoginToggle() async {
    if (_isLoggedIn) {
      final removePlatformCookiesUseCase = ref.read(
        removePlatformCookiesUseCaseProvider,
      );
      final result = await removePlatformCookiesUseCase(
        widget.platform.name.toLowerCase(),
      );
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() => _isLoggedIn = false);
        AppSnackBar.info(
          context,
          message: '${AppLocalizations.homeLogout} ${widget.platform.name}',
        );
      }
    } else if (widget.platform.loginUrl != null) {
      await showPlatformLoginDialog(
        context: context,
        platform: widget.platform.name,
        loginUrl: widget.platform.loginUrl!,
      );
      if (!mounted) return;
      _checkLoginStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final platform = widget.platform;
    final needsLightTint = isDark && platform.color.computeLuminance() < 0.15;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (platform.isOther) {
            ref.read(browserInitialUrlProvider.notifier).state =
                'https://www.google.com';
            ref
                .read(navigationProvider.notifier)
                .navigateToTab(NavigationConstants.browserIndex);
            return;
          }
          if (platform.url.isNotEmpty) {
            ref.read(browserInitialUrlProvider.notifier).state =
                'https://${platform.url}';
            ref
                .read(navigationProvider.notifier)
                .navigateToTab(NavigationConstants.browserIndex);
          }
        },
        onSecondaryTap:
            !platform.isOther && platform.loginUrl != null
                ? _handleLoginToggle
                : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
          decoration: BoxDecoration(
            color:
                _isLoggedIn
                    ? (isDark
                        ? AppColors.brand.withValues(
                          alpha:
                              _isHovered ? AppOpacity.subtle : AppOpacity.hover,
                        )
                        : cs.primaryContainer)
                    : _isHovered
                    ? (isDark
                        ? AppColors.homeDarkCardHover
                        : AppColors.lightSurface3)
                    : (isDark
                        ? AppColors.homeDarkCardBg
                        : AppColors.lightSurface2),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                _isLoggedIn
                    ? Border.all(
                      color:
                          isDark
                              ? AppColors.accentHighlight.withValues(
                                alpha: AppOpacity.scrim,
                              )
                              : AppColors.accentHighlight.withValues(
                                alpha: AppOpacity.quarter,
                              ),
                      width: 0.5,
                    )
                    : Border.all(
                      color:
                          isDark
                              ? (_isHovered
                                  ? AppColors.homeDarkBorderStrong
                                  : AppColors.homeDarkBorderSubtle)
                              : cs.outlineVariant.withValues(
                                alpha: AppOpacity.scrim,
                              ),
                      width: 0.5,
                    ),
            boxShadow:
                isDark && _isLoggedIn
                    ? [
                      BoxShadow(
                        color: AppColors.brand.withValues(
                          alpha: AppOpacity.hover,
                        ),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing dot for logged-in platforms
              if (_isLoggedIn && isDark) ...[
                AnimatedBuilder(
                  animation: _pulseController,
                  builder:
                      (context, _) => Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.accentHighlight.withValues(
                            alpha:
                                AppOpacity.secondary +
                                (_pulseController.value * AppOpacity.medium),
                          ),
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentHighlight.withValues(
                                alpha:
                                    _pulseController.value * AppOpacity.medium,
                              ),
                              blurRadius: 4 + (_pulseController.value * 4),
                            ),
                          ],
                        ),
                      ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              SvgPicture.asset(
                platform.svgPath,
                width: 14,
                height: 14,
                colorFilter:
                    needsLightTint
                        ? ColorFilter.mode(
                          AppColors.darkMetaText,
                          BlendMode.srcIn,
                        )
                        : null,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, __, ___) => Icon(
                      Icons.public_rounded,
                      size: 14,
                      color:
                          needsLightTint
                              ? AppColors.darkMetaText
                              : platform.color,
                    ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                platform.isOther ? AppLocalizations.homeBrowser : platform.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      isDark
                          ? (_isLoggedIn
                              ? AppColors.accentHighlight
                              : (_isHovered
                                  ? AppColors.darkLightText
                                  : AppColors.darkMetaText))
                          : cs.onSurface.withValues(
                            alpha:
                                _isHovered
                                    ? AppOpacity.nearOpaque
                                    : AppOpacity.secondary,
                          ),
                  fontWeight:
                      _isLoggedIn
                          ? FontWeight.w600
                          : (_isHovered ? FontWeight.w500 : FontWeight.w400),
                  letterSpacing: _isLoggedIn ? 0.3 : 0,
                ),
              ),
              // Legacy login indicator for light mode
              if (_isLoggedIn && !isDark) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.accentHighlight,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform information model
class PlatformInfo {
  final String name;
  final String url;
  final String svgPath;
  final Color color;
  final bool isOther;
  final String? loginUrl;

  const PlatformInfo({
    required this.name,
    required this.url,
    required this.svgPath,
    required this.color,
    this.isOther = false,
    this.loginUrl,
  });
}
