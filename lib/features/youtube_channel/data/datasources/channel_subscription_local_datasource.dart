import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/channel_info.dart';
import '../../domain/entities/subscribed_channel.dart' as domain;

/// Local datasource for channel subscription operations using Drift
class ChannelSubscriptionLocalDataSource {
  final AppDatabase _database;

  ChannelSubscriptionLocalDataSource(this._database);

  /// Get all subscribed channels
  Future<List<domain.SubscribedChannel>> getAllSubscriptions() async {
    final channels = await _database.getAllSubscribedChannels();
    return channels.map(_mapToDomain).toList();
  }

  /// Get channels with new videos
  Future<List<domain.SubscribedChannel>> getChannelsWithNewVideos() async {
    final channels = await _database.getChannelsWithNewVideos();
    return channels.map(_mapToDomain).toList();
  }

  /// Check if channel is subscribed
  Future<bool> isSubscribed(String channelId) async {
    return await _database.isChannelSubscribed(channelId);
  }

  /// Subscribe to a channel
  Future<void> subscribe(ChannelInfo channel) async {
    // Validate required fields
    if (channel.id.trim().isEmpty) {
      throw ArgumentError('Cannot subscribe: Channel ID is required');
    }
    if (channel.webpageUrl.trim().isEmpty) {
      throw ArgumentError('Cannot subscribe: Channel URL is required');
    }
    if (channel.title.trim().isEmpty) {
      throw ArgumentError('Cannot subscribe: Channel title is required');
    }

    appLogger.info('💡 Subscribing to: ${channel.title} (${channel.id})');

    final companion = SubscribedChannelsCompanion(
      channelId: Value(channel.id),
      channelName: Value(channel.title),
      channelHandle: Value(channel.channelHandle),
      thumbnail: Value(channel.thumbnail),
      subscriberCount: Value(channel.subscriberCount),
      videoCount: Value(channel.videoCount),
      webpageUrl: Value(channel.webpageUrl),
      description: Value(channel.description),
      subscribedAt: Value(DateTime.now()),
      hasNewVideos: const Value(false),
    );

    await _database.subscribeToChannel(companion);
    appLogger.info('💡 ✅ Successfully subscribed to: ${channel.title}');
  }

  /// Unsubscribe from a channel
  Future<void> unsubscribe(String channelId) async {
    await _database.unsubscribeFromChannel(channelId);
    appLogger.info('Unsubscribed from channel: $channelId');
  }

  /// Update channel metadata
  Future<void> updateChannelInfo(String channelId, ChannelInfo channel) async {
    await _database.updateChannelInfo(
      channelId: channelId,
      channelName: channel.title,
      thumbnail: channel.thumbnail,
      subscriberCount: channel.subscriberCount,
      videoCount: channel.videoCount,
    );
  }

  /// Update latest video info
  Future<void> updateLatestVideo({
    required String channelId,
    required String videoId,
    required String videoTitle,
    required DateTime videoDate,
  }) async {
    await _database.updateChannelLatestVideo(
      channelId: channelId,
      latestVideoId: videoId,
      latestVideoTitle: videoTitle,
      latestVideoDate: videoDate,
    );
  }

  /// Set baseline latest video without marking as new.
  Future<void> setLatestVideoBaseline({
    required String channelId,
    required String videoId,
    required String videoTitle,
    required DateTime videoDate,
  }) async {
    await _database.setChannelLatestVideoBaseline(
      channelId: channelId,
      latestVideoId: videoId,
      latestVideoTitle: videoTitle,
      latestVideoDate: videoDate,
    );
  }

  /// Mark channel as viewed
  Future<void> markAsViewed(String channelId) async {
    await _database.markChannelAsViewed(channelId);
  }

  /// Update last checked timestamp
  Future<void> updateLastChecked(String channelId) async {
    await _database.updateChannelLastChecked(channelId);
  }

  /// Get subscribed channel by channel ID
  Future<domain.SubscribedChannel?> getByChannelId(String channelId) async {
    final channel = await _database.getSubscribedChannelByChannelId(channelId);
    return channel != null ? _mapToDomain(channel) : null;
  }

  /// Watch all subscriptions (reactive stream)
  Stream<List<domain.SubscribedChannel>> watchSubscriptions() {
    return _database.watchSubscribedChannels().map((channels) {
      return channels.map(_mapToDomain).toList();
    });
  }

  /// Watch new videos count
  Stream<int> watchNewVideosCount() {
    return _database.watchNewVideosCount();
  }

  /// Map database model to domain entity
  domain.SubscribedChannel _mapToDomain(SubscribedChannel dbChannel) {
    return domain.SubscribedChannel(
      id: dbChannel.id,
      channelId: dbChannel.channelId,
      channelName: dbChannel.channelName,
      channelHandle: dbChannel.channelHandle,
      thumbnail: dbChannel.thumbnail,
      subscriberCount: dbChannel.subscriberCount,
      videoCount: dbChannel.videoCount,
      webpageUrl: dbChannel.webpageUrl,
      description: dbChannel.description,
      subscribedAt: dbChannel.subscribedAt,
      lastChecked: dbChannel.lastChecked,
      latestVideoId: dbChannel.latestVideoId,
      latestVideoTitle: dbChannel.latestVideoTitle,
      latestVideoDate: dbChannel.latestVideoDate,
      hasNewVideos: dbChannel.hasNewVideos,
    );
  }
}
