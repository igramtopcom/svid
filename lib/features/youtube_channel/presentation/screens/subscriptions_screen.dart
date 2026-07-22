import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/subscribed_channel.dart';
import '../providers/channel_subscriptions_provider.dart';
import '../providers/youtube_channel_provider.dart';
import '../widgets/subscribed_channel_card.dart';
import '../widgets/subscription_card_skeleton.dart';
import 'channel_video_list_screen.dart';

/// Channel subscriptions surface for Explore.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  final Function(List<String> urls)? onDownloadSelected;
  final bool embedded;

  const SubscriptionsScreen({
    super.key,
    this.onDownloadSelected,
    this.embedded = false,
  });

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  bool _isChecking = false;
  bool _showingChannelDetail = false;
  final _searchController = TextEditingController();
  final _channelUrlController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _channelUrlController.addListener(_onChannelUrlChanged);
  }

  @override
  void dispose() {
    _channelUrlController.removeListener(_onChannelUrlChanged);
    _searchController.dispose();
    _channelUrlController.dispose();
    super.dispose();
  }

  Future<void> _checkForNewVideos() async {
    setState(() => _isChecking = true);

    try {
      final notifier = ref.read(channelSubscriptionNotifierProvider.notifier);
      final count = await notifier.checkAllForNewVideos();

      if (!mounted) return;

      AppSnackBar.info(
        context,
        message:
            count > 0
                ? AppLocalizations.subscriptionsFoundNewVideos(
                  count,
                  count == 1
                      ? AppLocalizations.subscriptionsFoundNewVideosChannel
                      : AppLocalizations.subscriptionsFoundNewVideosChannels,
                )
                : AppLocalizations.subscriptionsAllUpToDate,
      );
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _openChannel(String channelId, String webpageUrl) {
    ref
        .read(channelSubscriptionNotifierProvider.notifier)
        .markAsViewed(channelId);

    if (webpageUrl.isEmpty) {
      AppSnackBar.error(
        context,
        message: AppLocalizations.subscriptionsCannotOpenChannel,
      );
      return;
    }

    ref.read(youtubeChannelProvider.notifier).loadChannel(webpageUrl);
    setState(() => _showingChannelDetail = true);
  }

  void _openManualChannel() {
    final input = _channelUrlController.text.trim();
    if (input.isEmpty) return;

    ref.read(youtubeChannelProvider.notifier).loadChannel(input);
    setState(() => _showingChannelDetail = true);
  }

  void _closeChannelDetail() {
    ref.read(youtubeChannelProvider.notifier).clear();
    setState(() => _showingChannelDetail = false);
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.toLowerCase().trim());
  }

  void _onChannelUrlChanged() {
    if (mounted) setState(() {});
  }

  List<SubscribedChannel> _filterSubscriptions(List<SubscribedChannel> all) {
    if (_searchQuery.isEmpty) return all;
    return all.where((ch) {
      final nameMatch = ch.channelName.toLowerCase().contains(_searchQuery);
      final handleMatch =
          ch.channelHandle?.toLowerCase().contains(_searchQuery) ?? false;
      return nameMatch || handleMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionsAsync = ref.watch(subscribedChannelsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    final content = Stack(
      children: [
        if (!widget.embedded) Positioned.fill(child: ColoredBox(color: pageBg)),
        Column(
          children: [
            if (!_showingChannelDetail) ...[
              if (!widget.embedded) _buildCommandHeader(isDark),
              _buildManualChannelInput(isDark),
            ],
            Expanded(
              child: subscriptionsAsync.when(
                data: (allSubscriptions) {
                  // Opening a channel (from the "@ Enter channel URL" box) must
                  // render the detail screen FIRST — even with 0 subscriptions —
                  // so its loading/error is visible. Previously the empty-state
                  // short-circuited here, so a bad handle just hid the input
                  // with no feedback.
                  if (_showingChannelDetail) {
                    return ChannelVideoListScreen(
                      embedded: true,
                      onBack: _closeChannelDetail,
                      onDownloadSelected: widget.onDownloadSelected,
                    );
                  }

                  if (allSubscriptions.isEmpty) {
                    return _buildEmptyState(isDark);
                  }

                  final subscriptions = _filterSubscriptions(allSubscriptions);

                  return Column(
                    children: [
                      _buildChannelCount(
                        allSubscriptions.length,
                        subscriptions.length,
                        isDark,
                      ),
                      Expanded(
                        child:
                            subscriptions.isEmpty
                                ? _buildNoResults(isDark)
                                : _buildChannelList(subscriptions, isDark),
                      ),
                      _buildBottomAccent(isDark),
                    ],
                  );
                },
                loading: () => _buildLoadingSkeleton(),
                error: (error, stack) => _buildErrorState(isDark),
              ),
            ),
          ],
        ),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(backgroundColor: pageBg, body: content);
  }

  /// Command header.
  Widget _buildCommandHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.mdLg,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Wifi icon — filled, wine-red
              Icon(
                Icons.wifi,
                size: 14,
                color:
                    isDark
                        ? AppColors.brand
                        : AppColors.brand.withValues(alpha: AppOpacity.strong),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.subscriptionsTitle,
                  style: AppTypography.compact.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: isDark ? AppColors.accentHighlight : AppColors.brand,
                  ),
                ),
              ),
              // Sweep/refresh button — circular wine-red border
              if (_isChecking)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.brand.withValues(
                        alpha: AppOpacity.medium,
                      ),
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: BrandConfig.current.colors.gradientTail,
                      ),
                    ),
                  ),
                )
              else
                _SweepButton(onPressed: _checkForNewVideos, isDark: isDark),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: AppColors.border(context)),
        ],
      ),
    );
  }

  Widget _buildManualChannelInput(bool isDark) {
    const commandBarHeight = 48.0;
    final cs = Theme.of(context).colorScheme;
    final horizontal = widget.embedded ? AppSpacing.lg : AppSpacing.xl;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, AppSpacing.mdLg, horizontal, 0),
      child: SizedBox(
        height: commandBarHeight,
        child: TextField(
          controller: _channelUrlController,
          onSubmitted: (_) => _openManualChannel(),
          style: AppTypography.input.copyWith(
            color: isDark ? AppColors.darkLightText : Colors.black,
          ),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: AppLocalizations.subscriptionsUrlPlaceholder,
            hintStyle: AppTypography.input.copyWith(
              color:
                  isDark
                      ? AppColors.darkMetaText
                      : cs.onSurface.withValues(alpha: AppOpacity.secondary),
            ),
            prefixIcon: Icon(
              Icons.alternate_email_rounded,
              size: 18,
              color: isDark ? AppColors.darkLightText : cs.onSurfaceVariant,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              maxHeight: commandBarHeight,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.smMd),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? AppColors.homeDarkCardBg
                          : AppColors.surface3(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: IconButton(
                  icon: Icon(
                    _channelUrlController.text.isNotEmpty
                        ? Icons.arrow_forward_rounded
                        : Icons.content_paste_rounded,
                    size: 16,
                    color:
                        isDark
                            ? AppColors.homeDarkTextSecondary
                            : cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    if (_channelUrlController.text.isNotEmpty) {
                      _openManualChannel();
                    }
                  },
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            filled: true,
            fillColor:
                isDark ? AppColors.homeDarkAppBg : AppColors.lightSurface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkInputBorder
                        : AppColors.border(context),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkInputBorder
                        : AppColors.border(context),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              borderSide: BorderSide(
                color: AppColors.accentHighlight,
                width: isDark ? 1.75 : 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
            ),
            isDense: false,
          ),
        ),
      ),
    );
  }

  /// Channel count and quick filter.
  Widget _buildChannelCount(int total, int filtered, bool isDark) {
    final text =
        _searchQuery.isEmpty
            ? AppLocalizations.subscriptionsActiveFeeds(total)
            : AppLocalizations.subscriptionsFilteredFeeds(filtered, total);

    final horizontal = widget.embedded ? AppSpacing.lg : AppSpacing.xl;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.md,
        horizontal,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final label = Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.metadata.copyWith(
              fontWeight: FontWeight.w600,
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : AppColors.lightMetaText,
            ),
          );
          final search = SizedBox(
            width: compact ? double.infinity : 250,
            height: 32,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: AppTypography.compact.copyWith(
                fontWeight: FontWeight.w400,
                color:
                    isDark ? AppColors.darkLightText : AppColors.darkSurface1,
              ),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: AppLocalizations.subscriptionsSearchPlaceholder,
                hintStyle: AppTypography.compact.copyWith(
                  fontWeight: FontWeight.w400,
                  color:
                      isDark
                          ? AppColors.homeDarkTextMuted
                          : AppColors.lightMuted,
                ),
                prefixIcon: Icon(
                  Icons.radar_outlined,
                  size: 15,
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : AppColors.lightMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                  maxHeight: 32,
                ),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 14,
                            color:
                                isDark
                                    ? AppColors.homeDarkTextSecondary
                                    : AppColors.lightMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                        )
                        : null,
                filled: true,
                fillColor:
                    isDark
                        ? AppColors.homeDarkCardBg
                        : AppColors.surface1(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color:
                        isDark
                            ? AppColors.homeDarkInputBorder
                            : AppColors.border(context),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.accentHighlight,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                isDense: false,
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: AppSpacing.sm), search],
            );
          }

          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: AppSpacing.md),
              search,
            ],
          );
        },
      ),
    );
  }

  /// Channel list
  Widget _buildChannelList(List<SubscribedChannel> subscriptions, bool isDark) {
    final horizontal = widget.embedded ? AppSpacing.lg : AppSpacing.xl;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.sm,
        horizontal,
        AppSpacing.lg,
      ),
      itemCount: subscriptions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final subscription = subscriptions[index];
        return SubscribedChannelCard(
          subscription: subscription,
          onTap:
              () =>
                  _openChannel(subscription.channelId, subscription.webpageUrl),
        );
      },
    );
  }

  /// No search results
  Widget _buildNoResults(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 32,
            color:
                isDark ? AppColors.homeDarkTextSecondary : AppColors.lightMuted,
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            'No channels match "$_searchQuery"',
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w400,
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : AppColors.lightMetaText,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state.
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                      color: AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.secondary,
                      ),
                    ),
                  ),
                ),
                Icon(
                  Icons.subscriptions_outlined,
                  size: 44,
                  color:
                      isDark
                          ? AppColors.brand.withValues(alpha: AppOpacity.medium)
                          : AppColors.brand.withValues(
                            alpha: AppOpacity.quarter,
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.subscriptionsEmpty,
            style: AppTypography.sectionHeader.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: isDark ? AppColors.darkLightText : AppColors.lightMetaText,
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                AppLocalizations.subscriptionsEmptyDescription,
                textAlign: TextAlign.center,
                style: AppTypography.statusBadge.copyWith(
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : AppColors.lightMetaText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Error state — Nocturne styled
  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 36,
            color:
                isDark
                    ? AppColors.accentHighlight.withValues(
                      alpha: AppOpacity.secondary,
                    )
                    : AppColors.errorRed,
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            'Failed to load subscriptions',
            style: AppTypography.metadata.copyWith(
              color: isDark ? AppColors.darkLightText : AppColors.lightMetaText,
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          TextButton.icon(
            onPressed: () => ref.invalidate(subscribedChannelsStreamProvider),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(AppLocalizations.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    final padding = widget.embedded ? AppSpacing.lg : AppSpacing.xl;
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: List.generate(6, (_) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: SubscriptionCardSkeleton(),
          );
        }),
      ),
    );
  }

  Widget _buildBottomAccent(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.sm,
      ),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              AppColors.brand.withValues(
                alpha: isDark ? AppOpacity.scrim : AppOpacity.pressed,
              ),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular sweep/refresh button — wine-red border
class _SweepButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isDark;

  const _SweepButton({required this.onPressed, required this.isDark});

  @override
  State<_SweepButton> createState() => _SweepButtonState();
}

class _SweepButtonState extends State<_SweepButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color:
                  _hovered
                      ? AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.secondary,
                      )
                      : AppColors.brand.withValues(alpha: AppOpacity.medium),
            ),
            color:
                _hovered
                    ? AppColors.brand.withValues(alpha: AppOpacity.pressed)
                    : Colors.transparent,
          ),
          child: Center(
            child: AnimatedRotation(
              turns: _hovered ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 700),
              child: Icon(
                Icons.refresh,
                size: 18,
                color:
                    widget.isDark
                        ? BrandConfig.current.colors.gradientTail
                        : AppColors.brand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
