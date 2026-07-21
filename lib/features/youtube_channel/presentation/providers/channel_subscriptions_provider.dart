import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';
import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/notification_center_provider.dart';
import '../../../../core/services/notification_center_service.dart';
import '../../../../core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/datasources/channel_subscription_local_datasource.dart';
import '../../data/repositories/channel_subscription_repository_impl.dart';
import '../../data/repositories/youtube_channel_repository.dart';
import '../../domain/entities/channel_info.dart';
import '../../domain/entities/subscribed_channel.dart' as domain;
import '../../domain/repositories/channel_subscription_repository.dart';

/// Provider for channel subscription local datasource
final _channelSubscriptionLocalDataSourceProvider =
    Provider<ChannelSubscriptionLocalDataSource>((ref) {
      final database = ref.watch(databaseProvider);
      return ChannelSubscriptionLocalDataSource(database);
    });

/// Provider for YouTube channel repository (for checking new videos)
final _youtubeChannelRepositoryProvider = FutureProvider<
  YouTubeChannelRepository
>((ref) async {
  final ytdlpPath = await ref.watch(
    binaryPathProvider(BinaryType.ytDlp).future,
  );
  if (ytdlpPath == null) {
    throw Exception('yt-dlp binary not found');
  }
  final denoPath = await ref.watch(binaryPathProvider(BinaryType.deno).future);
  return YouTubeChannelRepository(binaryPath: ytdlpPath, denoPath: denoPath);
});

/// Provider for channel subscription repository
final channelSubscriptionRepositoryProvider =
    FutureProvider<ChannelSubscriptionRepository>((ref) async {
      final localDataSource = ref.watch(
        _channelSubscriptionLocalDataSourceProvider,
      );
      final channelRepository = await ref.watch(
        _youtubeChannelRepositoryProvider.future,
      );

      return ChannelSubscriptionRepositoryImpl(
        localDataSource: localDataSource,
        channelRepository: channelRepository,
      );
    });

/// State provider for subscription search query
final subscriptionSearchQueryProvider = StateProvider<String>((ref) => '');

/// Stream provider for all subscribed channels
final subscribedChannelsStreamProvider =
    StreamProvider<List<domain.SubscribedChannel>>((ref) {
      final localDataSource = ref.watch(
        _channelSubscriptionLocalDataSourceProvider,
      );
      return localDataSource.watchSubscriptions();
    });

/// Stream provider for filtered subscribed channels (with search)
final filteredSubscribedChannelsProvider =
    StreamProvider<List<domain.SubscribedChannel>>((ref) {
      final subscriptionsAsync = ref.watch(subscribedChannelsStreamProvider);
      final searchQuery =
          ref.watch(subscriptionSearchQueryProvider).toLowerCase().trim();

      return subscriptionsAsync.when(
        data: (subscriptions) {
          if (searchQuery.isEmpty) {
            return Stream.value(subscriptions);
          }

          // Filter by channel name or handle
          final filtered =
              subscriptions.where((channel) {
                final nameMatch = channel.channelName.toLowerCase().contains(
                  searchQuery,
                );
                final handleMatch =
                    channel.channelHandle?.toLowerCase().contains(
                      searchQuery,
                    ) ??
                    false;
                return nameMatch || handleMatch;
              }).toList();

          return Stream.value(filtered);
        },
        loading: () => const Stream.empty(),
        error: (error, stack) => Stream.error(error, stack),
      );
    });

/// Stream provider for new videos count (badge)
final newVideosCountStreamProvider = StreamProvider<int>((ref) {
  final localDataSource = ref.watch(
    _channelSubscriptionLocalDataSourceProvider,
  );
  return localDataSource.watchNewVideosCount();
});

/// Provider to check if a specific channel is subscribed
final isChannelSubscribedProvider = FutureProvider.family<bool, String>((
  ref,
  channelId,
) async {
  final repository = await ref.watch(
    channelSubscriptionRepositoryProvider.future,
  );
  final result = await repository.isSubscribed(channelId);
  return result.when(
    success: (isSubscribed) => isSubscribed,
    failure: (_) => false,
  );
});

/// State notifier for subscription actions
class ChannelSubscriptionNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  ChannelSubscriptionRepository? _repository;

  static const _notifiedVideoKeysStorageKey = 'subscription_notified_video_keys';

  /// Persisted channelId:videoId pairs already notified, survives restart.
  Set<String> _notifiedVideoKeys = {};
  bool _notifiedKeysLoaded = false;

  ChannelSubscriptionNotifier(this._ref) : super(const AsyncValue.data(null)) {
    _initRepository();
  }

  Future<void> _initRepository() async {
    _repository = await _ref.read(channelSubscriptionRepositoryProvider.future);
  }

  Future<ChannelSubscriptionRepository> get _repo async {
    if (_repository != null) return _repository!;
    _repository = await _ref.read(channelSubscriptionRepositoryProvider.future);
    return _repository!;
  }

  /// Subscribe to a channel
  Future<void> subscribe(ChannelInfo channel) async {
    state = const AsyncValue.loading();
    final repository = await _repo;
    final result = await repository.subscribe(channel);
    state = result.when(
      success: (_) {
        appLogger.info('✅ Subscribed to ${channel.title}');
        return const AsyncValue.data(null);
      },
      failure: (error) {
        appLogger.error('Failed to subscribe', error);
        return AsyncValue.error(error, StackTrace.current);
      },
    );
  }

  /// Unsubscribe from a channel
  Future<void> unsubscribe(String channelId) async {
    state = const AsyncValue.loading();
    final repository = await _repo;
    final result = await repository.unsubscribe(channelId);
    state = result.when(
      success: (_) {
        appLogger.info('❌ Unsubscribed from channel');
        return const AsyncValue.data(null);
      },
      failure: (error) {
        appLogger.error('Failed to unsubscribe', error);
        return AsyncValue.error(error, StackTrace.current);
      },
    );
  }

  /// Check all channels for new videos and fire notifications.
  /// Sets UI loading state — use for manual Sweep button.
  Future<int> checkAllForNewVideos() async {
    state = const AsyncValue.loading();
    final repository = await _repo;
    final result = await repository.checkAllChannelsForNewVideos();
    return await result.when(
      success: (count) async {
        state = const AsyncValue.data(null);
        appLogger.info('Found $count channels with new videos');
        if (count > 0) await _fireNewVideoNotifications();
        return count;
      },
      failure: (error) async {
        state = AsyncValue.error(error, StackTrace.current);
        appLogger.error('Failed to check for new videos', error);
        return 0;
      },
    );
  }

  /// Silent check — no UI loading state. Use for background auto poll.
  Future<int> checkAllForNewVideosSilent() async {
    final repository = await _repo;
    final result = await repository.checkAllChannelsForNewVideos();
    return await result.when(
      success: (count) async {
        if (count > 0) await _fireNewVideoNotifications();
        return count;
      },
      failure: (error) async {
        appLogger.error('Failed to check for new videos', error);
        return 0;
      },
    );
  }

  Future<void> _loadNotifiedKeys() async {
    if (_notifiedKeysLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_notifiedVideoKeysStorageKey);
      if (json != null) {
        final list = (jsonDecode(json) as List).cast<String>();
        _notifiedVideoKeys = list.toSet();
      }
    } catch (_) {}
    _notifiedKeysLoaded = true;
  }

  Future<void> _saveNotifiedKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only last 200 keys to bound storage
      final keys = _notifiedVideoKeys.toList();
      if (keys.length > 200) {
        _notifiedVideoKeys = keys.sublist(keys.length - 200).toSet();
      }
      await prefs.setString(
        _notifiedVideoKeysStorageKey,
        jsonEncode(_notifiedVideoKeys.toList()),
      );
    } catch (_) {}
  }

  /// Fire Activity Center + OS toast for channels with new videos.
  /// Shared by both manual Sweep and auto poll.
  Future<void> _fireNewVideoNotifications() async {
    try {
      await _loadNotifiedKeys();

      final localDataSource = _ref.read(
        _channelSubscriptionLocalDataSourceProvider,
      );
      final channels = await localDataSource.getChannelsWithNewVideos();

      var didNotify = false;
      for (final channel in channels) {
        final videoId = channel.latestVideoId;
        if (videoId == null || channel.channelName.isEmpty) continue;

        final dedupeKey = '${channel.channelId}:$videoId';
        if (_notifiedVideoKeys.contains(dedupeKey)) continue;
        _notifiedVideoKeys.add(dedupeKey);
        didNotify = true;

        // Activity Center entry (always)
        try {
          _ref.read(notificationCenterServiceProvider).add(
            AppNotificationType.youtubeNewVideo,
            '${channel.channelName} uploaded a new video',
            channel.latestVideoTitle ?? 'New video available',
            metadata: {
              'channelId': channel.channelId,
              if (videoId.isNotEmpty) 'videoId': videoId,
              'channelUrl': channel.webpageUrl,
            },
          );
        } catch (_) {}

        // OS toast (gated by notification setting)
        try {
          final enabled = _ref.read(settingsProvider).notificationsEnabled;
          if (enabled) {
            await notificationService.show(
              title: '🎬 ${channel.channelName}',
              body: channel.latestVideoTitle ?? 'New video available',
            );
          }
        } catch (_) {}
      }

      if (didNotify) await _saveNotifiedKeys();
    } catch (e) {
      appLogger.debug('Notification bridge failed (non-fatal): $e');
    }
  }

  /// Mark channel as viewed
  Future<void> markAsViewed(String channelId) async {
    final repository = await _repo;
    final result = await repository.markChannelAsViewed(channelId);
    result.when(
      success: (_) => appLogger.info('Marked channel as viewed'),
      failure: (error) => appLogger.error('Failed to mark as viewed', error),
    );
  }
}

/// Provider for subscription actions
final channelSubscriptionNotifierProvider =
    StateNotifierProvider<ChannelSubscriptionNotifier, AsyncValue<void>>((ref) {
      return ChannelSubscriptionNotifier(ref);
    });
