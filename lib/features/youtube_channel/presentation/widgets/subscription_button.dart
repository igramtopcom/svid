import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/channel_info.dart';
import '../../domain/entities/subscribed_channel.dart' as domain;
import '../providers/channel_subscriptions_provider.dart';

/// Subscribe/Unsubscribe toggle — Nocturne Cinematic capsule style
/// "MONITORING" when subscribed, "INITIATE SURVEILLANCE" when not
/// Design ref: Stitch screen aeb19b1031ea45b4b26f3cfbf57f0cc6
class SubscriptionButton extends ConsumerStatefulWidget {
  final ChannelInfo channel;

  const SubscriptionButton({super.key, required this.channel});

  @override
  ConsumerState<SubscriptionButton> createState() => _SubscriptionButtonState();
}

class _SubscriptionButtonState extends ConsumerState<SubscriptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final subscriptionsAsync = ref.watch(subscribedChannelsStreamProvider);
    final subscriptionState = ref.watch(channelSubscriptionNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return subscriptionsAsync.when(
      data: (subscriptions) {
        final matchedSubscription = _findMatchedSubscription(subscriptions);
        final isSubscribed = matchedSubscription != null;
        return subscriptionState.when(
          data:
              (_) => _buildCapsule(
                context,
                ref,
                isSubscribed,
                false,
                isDark,
                matchedSubscription,
              ),
          loading:
              () => _buildCapsule(
                context,
                ref,
                isSubscribed,
                true,
                isDark,
                matchedSubscription,
              ),
          error:
              (_, __) => _buildCapsule(
                context,
                ref,
                isSubscribed,
                false,
                isDark,
                matchedSubscription,
              ),
        );
      },
      loading: () => _buildLoadingState(isDark),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  domain.SubscribedChannel? _findMatchedSubscription(
    List<domain.SubscribedChannel> subscriptions,
  ) {
    final channelId = widget.channel.id.trim().toLowerCase();
    final channelHandle = widget.channel.channelHandle?.trim().toLowerCase();
    final webpageUrl = widget.channel.webpageUrl.trim().toLowerCase();

    for (final subscription in subscriptions) {
      final subscriptionId = subscription.channelId.trim().toLowerCase();
      final subscriptionHandle =
          subscription.channelHandle?.trim().toLowerCase();
      final subscriptionUrl = subscription.webpageUrl.trim().toLowerCase();

      final isMatch =
          (channelId.isNotEmpty && subscriptionId == channelId) ||
          (channelHandle != null &&
              channelHandle.isNotEmpty &&
              subscriptionHandle == channelHandle) ||
          (webpageUrl.isNotEmpty && subscriptionUrl == webpageUrl);
      if (isMatch) return subscription;
    }

    return null;
  }

  Widget _buildLoadingState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdLg,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.darkMuted.withValues(alpha: AppOpacity.scrim)
                  : AppColors.lightMuted,
        ),
      ),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color:
              isDark
                  ? BrandConfig.current.colors.gradientTail
                  : AppColors.brand,
        ),
      ),
    );
  }

  Widget _buildCapsule(
    BuildContext context,
    WidgetRef ref,
    bool isSubscribed,
    bool isLoading,
    bool isDark,
    domain.SubscribedChannel? matchedSubscription,
  ) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap:
            isLoading
                ? null
                : () async {
                  final notifier = ref.read(
                    channelSubscriptionNotifierProvider.notifier,
                  );

                  if (isSubscribed) {
                    final unsubscribeChannelId =
                        matchedSubscription?.channelId ?? widget.channel.id;
                    await notifier.unsubscribe(unsubscribeChannelId);
                    final success =
                        !ref.read(channelSubscriptionNotifierProvider).hasError;
                    if (context.mounted) {
                      if (success) {
                        AppSnackBar.info(
                          context,
                          message: AppLocalizations.subscriptionsUnsubscribedFrom(
                            widget.channel.title,
                          ),
                        );
                        ref.invalidate(
                          isChannelSubscribedProvider(unsubscribeChannelId),
                        );
                      } else {
                        AppSnackBar.error(
                          context,
                          message: AppLocalizations
                              .subscriptionsFailedToUnsubscribe(
                            widget.channel.title,
                          ),
                        );
                      }
                    }
                  } else {
                    await notifier.subscribe(widget.channel);
                    final success =
                        !ref.read(channelSubscriptionNotifierProvider).hasError;
                    if (context.mounted) {
                      if (success) {
                        AppSnackBar.success(
                          context,
                          message: AppLocalizations.subscriptionsSubscribedTo(
                            widget.channel.title,
                          ),
                        );
                        ref.invalidate(
                          isChannelSubscribedProvider(widget.channel.id),
                        );
                      } else {
                        AppSnackBar.error(
                          context,
                          message:
                              AppLocalizations.subscriptionsFailedToSubscribe(
                            widget.channel.title,
                          ),
                        );
                      }
                    }
                  }
                },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdLg,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? AppColors.brand.withValues(
                        alpha:
                            _hovered
                                ? AppOpacity.nearOpaque
                                : AppOpacity.overlay,
                      )
                      : AppColors.brand.withValues(alpha: AppOpacity.secondary),
            ),
            color:
                isSubscribed && isDark
                    ? (_hovered
                        ? AppColors.brand.withValues(alpha: AppOpacity.subtle)
                        : AppColors.brand.withValues(alpha: AppOpacity.divider))
                    : (_hovered && isDark
                        ? AppColors.brand.withValues(alpha: AppOpacity.pressed)
                        : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color:
                        isDark
                            ? BrandConfig.current.colors.gradientTail
                            : AppColors.brand,
                  ),
                )
              else
                Icon(
                  isSubscribed ? Icons.sensors : Icons.sensors_off_outlined,
                  size: 14,
                  color:
                      isDark
                          ? BrandConfig.current.colors.gradientTail
                          : AppColors.brand,
                ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isSubscribed ? 'MONITORING' : 'SUBSCRIBE',
                style: AppTypography.compact.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color:
                      isDark
                          ? BrandConfig.current.colors.gradientTail
                          : AppColors.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
