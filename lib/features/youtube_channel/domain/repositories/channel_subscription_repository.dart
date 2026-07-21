import '../../../../core/errors/result.dart';
import '../entities/channel_info.dart';
import '../entities/subscribed_channel.dart';

/// Repository interface for channel subscription operations
abstract class ChannelSubscriptionRepository {
  /// Get all subscribed channels
  Future<Result<List<SubscribedChannel>>> getAllSubscriptions();

  /// Get channels with new videos (badge indicator)
  Future<Result<List<SubscribedChannel>>> getChannelsWithNewVideos();

  /// Check if a channel is subscribed
  Future<Result<bool>> isSubscribed(String channelId);

  /// Subscribe to a channel
  Future<Result<void>> subscribe(ChannelInfo channel);

  /// Unsubscribe from a channel
  Future<Result<void>> unsubscribe(String channelId);

  /// Check a specific channel for new videos
  /// Returns true if new videos were found
  Future<Result<bool>> checkChannelForNewVideos(String channelId);

  /// Check all subscribed channels for new videos
  /// Returns count of channels with new videos found
  Future<Result<int>> checkAllChannelsForNewVideos();

  /// Mark channel as viewed (clear new videos badge)
  Future<Result<void>> markChannelAsViewed(String channelId);

  /// Update channel metadata (subscriber count, video count, etc.)
  Future<Result<void>> updateChannelInfo(String channelId, ChannelInfo channel);

  /// Watch all subscribed channels (reactive stream)
  Stream<List<SubscribedChannel>> watchSubscriptions();

  /// Watch count of channels with new videos (for badge)
  Stream<int> watchNewVideosCount();
}
