import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/channel_info.dart';
import '../../domain/entities/subscribed_channel.dart';
import '../../domain/repositories/channel_subscription_repository.dart';
import '../datasources/channel_subscription_local_datasource.dart';
import './youtube_channel_repository.dart';

/// Implementation of channel subscription repository
class ChannelSubscriptionRepositoryImpl
    implements ChannelSubscriptionRepository {
  final ChannelSubscriptionLocalDataSource _localDataSource;
  final YouTubeChannelRepository _channelRepository;

  ChannelSubscriptionRepositoryImpl({
    required ChannelSubscriptionLocalDataSource localDataSource,
    required YouTubeChannelRepository channelRepository,
  }) : _localDataSource = localDataSource,
       _channelRepository = channelRepository;

  @override
  Future<Result<List<SubscribedChannel>>> getAllSubscriptions() async {
    return runCatching(() async {
      return await _localDataSource.getAllSubscriptions();
    });
  }

  @override
  Future<Result<List<SubscribedChannel>>> getChannelsWithNewVideos() async {
    return runCatching(() async {
      return await _localDataSource.getChannelsWithNewVideos();
    });
  }

  @override
  Future<Result<bool>> isSubscribed(String channelId) async {
    return runCatching(() async {
      return await _localDataSource.isSubscribed(channelId);
    });
  }

  @override
  Future<Result<void>> subscribe(ChannelInfo channel) async {
    // Validate required fields
    if (channel.id.trim().isEmpty) {
      return const Result.failure(
        AppException.validation(
          message: 'Cannot subscribe: Channel ID is required',
        ),
      );
    }
    if (channel.webpageUrl.trim().isEmpty) {
      return const Result.failure(
        AppException.validation(
          message: 'Cannot subscribe: Channel URL is required',
        ),
      );
    }
    if (channel.title.trim().isEmpty) {
      return const Result.failure(
        AppException.validation(
          message: 'Cannot subscribe: Channel title is required',
        ),
      );
    }

    return runCatching(() async {
      // Check if already subscribed
      final isSubscribed = await _localDataSource.isSubscribed(channel.id);
      if (isSubscribed) {
        appLogger.info('ℹ️ Already subscribed to channel: ${channel.title}');
        return;
      }

      // Fetch accurate channel metadata for subscription (especially avatar/thumbnail)
      // This ensures we always have the best quality avatar
      appLogger.info(
        '🔄 Fetching accurate channel metadata for subscription...',
      );

      final metadataResult = await _channelRepository.getChannelMetadata(
        url: channel.webpageUrl,
      );

      // Merge metadata with existing channel info
      final channelWithMetadata = metadataResult.when(
        success: (metadata) {
          appLogger.info(
            '✅ Got accurate metadata with thumbnail: ${metadata.thumbnail != null}',
          );
          // Merge: prefer metadata for thumbnail/description, keep other data from channel
          return ChannelInfo(
            id: channel.id, // Keep original ID
            title: channel.title, // Keep original title
            uploader: metadata.uploader ?? channel.uploader,
            uploaderId: metadata.uploaderId ?? channel.uploaderId,
            thumbnail:
                metadata.thumbnail ??
                channel.thumbnail, // Prefer metadata thumbnail
            description: metadata.description ?? channel.description,
            subscriberCount:
                metadata.subscriberCount ?? channel.subscriberCount,
            videoCount: channel.videoCount, // Keep original video count
            webpageUrl: channel.webpageUrl, // Keep original URL
          );
        },
        failure: (error) {
          // If metadata fetch fails, use the channel info we already have
          appLogger.warning(
            '⚠️ Failed to fetch metadata: $error. Using existing channel info.',
          );
          return channel;
        },
      );

      // Subscribe with validated and enriched data
      await _localDataSource.subscribe(channelWithMetadata);
      appLogger.info(
        '💡 ✅ Subscribed to channel: ${channelWithMetadata.title}',
      );

      // Baseline: fetch latest video so first check doesn't false-positive.
      // Awaited so latestVideoId is guaranteed set before any poll runs.
      try {
        final baselineResult = await _channelRepository.getChannelInfo(
          url: channelWithMetadata.webpageUrl,
          startIndex: 0,
          endIndex: 1,
        );
        await baselineResult.when(
          success: (data) async {
            final (_, videos) = data;
            if (videos.isNotEmpty) {
              final latest = videos.first;
              DateTime? videoDate;
              if (latest.uploadDate != null) {
                try {
                  final d = latest.uploadDate!;
                  if (d.length == 8) {
                    videoDate = DateTime(
                      int.parse(d.substring(0, 4)),
                      int.parse(d.substring(4, 6)),
                      int.parse(d.substring(6, 8)),
                    );
                  }
                } catch (_) {}
              }
              await _localDataSource.setLatestVideoBaseline(
                channelId: channelWithMetadata.id,
                videoId: latest.id,
                videoTitle: latest.title,
                videoDate: videoDate ?? DateTime.now(),
              );
              appLogger.info('📌 Baseline set: ${latest.title}');
            }
          },
          failure: (e) async {
            appLogger.warning('⚠️ Baseline fetch failed (non-fatal): $e');
          },
        );
      } catch (e) {
        appLogger.warning('⚠️ Baseline fetch failed (non-fatal): $e');
      }
    });
  }

  @override
  Future<Result<void>> unsubscribe(String channelId) async {
    return runCatching(() async {
      await _localDataSource.unsubscribe(channelId);
      appLogger.info('❌ Unsubscribed from channel: $channelId');
    });
  }

  @override
  Future<Result<bool>> checkChannelForNewVideos(String channelId) async {
    return runCatching(() async {
      appLogger.info('🔍 Checking channel for new videos: $channelId');

      // Get subscribed channel from DB
      final subscribedChannel = await _localDataSource.getByChannelId(
        channelId,
      );
      if (subscribedChannel == null) {
        appLogger.warning('Channel not found in subscriptions: $channelId');
        return false;
      }

      // Validate webpageUrl is available
      if (subscribedChannel.webpageUrl.isEmpty) {
        appLogger.error('Channel has no URL stored: $channelId');
        return false;
      }

      // Fetch latest video from channel (only first video)
      final result = await _channelRepository.getChannelInfo(
        url: subscribedChannel.webpageUrl,
        startIndex: 0,
        endIndex: 1, // Only get latest video
      );

      return await result.when(
        success: (data) async {
          final (channelInfo, videos) = data;

          // Skip metadata update entirely for latest-video polls (range 0-1).
          // The parser sets videoCount=lines.length (always 1 here) and may
          // return degraded title/subscriberCount/thumbnail, clobbering the
          // rich metadata stored at subscribe time.

          if (videos.isEmpty) {
            appLogger.info('No videos found for channel: $channelId');
            await _localDataSource.updateLastChecked(channelId);
            return false;
          }

          final latestVideo = videos.first;
          final hasNewVideo = subscribedChannel.latestVideoId != latestVideo.id;

          if (hasNewVideo) {
            // New video found!
            appLogger.info('🆕 New video found: ${latestVideo.title}');

            // Parse upload date
            DateTime? videoDate;
            if (latestVideo.uploadDate != null) {
              try {
                // YouTube upload date format: YYYYMMDD
                final dateStr = latestVideo.uploadDate!;
                if (dateStr.length == 8) {
                  videoDate = DateTime(
                    int.parse(dateStr.substring(0, 4)),
                    int.parse(dateStr.substring(4, 6)),
                    int.parse(dateStr.substring(6, 8)),
                  );
                }
              } catch (e) {
                appLogger.warning(
                  'Failed to parse upload date: ${latestVideo.uploadDate}',
                );
              }
            }

            await _localDataSource.updateLatestVideo(
              channelId: channelId,
              videoId: latestVideo.id,
              videoTitle: latestVideo.title,
              videoDate: videoDate ?? DateTime.now(),
            );
            return true;
          } else {
            appLogger.info(
              'No new videos for channel: ${subscribedChannel.channelName}',
            );
            await _localDataSource.updateLastChecked(channelId);
            return false;
          }
        },
        failure: (error) {
          appLogger.error('Failed to check channel for new videos', error);
          return false;
        },
      );
    });
  }

  @override
  Future<Result<int>> checkAllChannelsForNewVideos() async {
    return runCatching(() async {
      appLogger.info('🔍 Checking all subscribed channels for new videos...');

      final subscriptions = await _localDataSource.getAllSubscriptions();
      if (subscriptions.isEmpty) {
        appLogger.info('No subscribed channels to check');
        return 0;
      }

      int newVideosCount = 0;
      const batchSize = 5; // Process 5 channels concurrently
      const delayBetweenBatches = Duration(milliseconds: 500);

      // Process channels in batches to avoid rate limiting
      for (int i = 0; i < subscriptions.length; i += batchSize) {
        final batch = subscriptions.skip(i).take(batchSize).toList();

        // Check channels in this batch concurrently
        final results = await Future.wait(
          batch.map((channel) async {
            try {
              final result = await checkChannelForNewVideos(channel.channelId);
              return result.isSuccess && result.dataOrNull == true;
            } catch (e) {
              appLogger.error(
                'Error checking channel ${channel.channelName}',
                e,
              );
              return false;
            }
          }),
        );

        // Count new videos from this batch
        newVideosCount += results.where((hasNew) => hasNew).length;

        // Small delay between batches to avoid overwhelming the API
        if (i + batchSize < subscriptions.length) {
          await Future.delayed(delayBetweenBatches);
        }
      }

      appLogger.info(
        '✅ Checked ${subscriptions.length} channels, found $newVideosCount with new videos',
      );
      return newVideosCount;
    });
  }

  @override
  Future<Result<void>> markChannelAsViewed(String channelId) async {
    return runCatching(() async {
      await _localDataSource.markAsViewed(channelId);
    });
  }

  @override
  Future<Result<void>> updateChannelInfo(
    String channelId,
    ChannelInfo channel,
  ) async {
    return runCatching(() async {
      await _localDataSource.updateChannelInfo(channelId, channel);
    });
  }

  @override
  Stream<List<SubscribedChannel>> watchSubscriptions() {
    return _localDataSource.watchSubscriptions();
  }

  @override
  Stream<int> watchNewVideosCount() {
    return _localDataSource.watchNewVideosCount();
  }
}
