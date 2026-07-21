import 'dart:async';

import '../logging/app_logger.dart';
import '../../features/youtube_channel/data/datasources/channel_subscription_local_datasource.dart';
import '../../features/youtube_channel/presentation/providers/channel_subscriptions_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Periodically checks subscribed YouTube channels for new videos.
///
/// Notification bridging (Activity Center + OS toast) is handled by
/// [ChannelSubscriptionNotifier.checkAllForNewVideos], which is shared
/// with the manual Sweep button path — this service just triggers the check.
///
/// Starts after a settle delay (60s) to avoid blocking app launch, then
/// polls every 45 minutes. All errors are swallowed.
class SubscriptionPollService {
  final ChannelSubscriptionLocalDataSource _localDataSource;
  final ProviderContainer _container;
  Timer? _timer;

  static const _settleDelay = Duration(seconds: 60);
  static const _pollInterval = Duration(minutes: 45);

  SubscriptionPollService({
    required ChannelSubscriptionLocalDataSource localDataSource,
    required ProviderContainer container,
  })  : _localDataSource = localDataSource,
        _container = container;

  void start() {
    _timer?.cancel();
    _timer = Timer(_settleDelay, () {
      _poll();
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    });
    appLogger.info(
      '[SubscriptionPoll] Scheduled: settle=${_settleDelay.inSeconds}s, '
      'interval=${_pollInterval.inMinutes}min',
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final subscriptions = await _localDataSource.getAllSubscriptions();
      if (subscriptions.isEmpty) return;

      appLogger.debug(
        '[SubscriptionPoll] Checking ${subscriptions.length} channels...',
      );

      final notifier = _container.read(
        channelSubscriptionNotifierProvider.notifier,
      );
      final count = await notifier.checkAllForNewVideosSilent();

      appLogger.debug(
        '[SubscriptionPoll] Done. $count channels with new videos.',
      );
    } catch (e) {
      appLogger.debug('[SubscriptionPoll] Poll failed (non-fatal): $e');
    }
  }
}
