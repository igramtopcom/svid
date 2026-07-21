import 'package:freezed_annotation/freezed_annotation.dart';

import '../mixins/formatted_channel_mixin.dart';

part 'subscribed_channel.freezed.dart';

@freezed
class SubscribedChannel with _$SubscribedChannel, FormattedChannelMixin {
  const SubscribedChannel._();

  const factory SubscribedChannel({
    required int id,
    required String channelId,
    required String channelName,
    String? channelHandle,
    String? thumbnail,
    int? subscriberCount,
    int? videoCount,
    required String webpageUrl,
    String? description,
    required DateTime subscribedAt,
    DateTime? lastChecked,
    String? latestVideoId,
    String? latestVideoTitle,
    DateTime? latestVideoDate,
    @Default(false) bool hasNewVideos,
  }) = _SubscribedChannel;

  /// Get channel handle (@username) or fallback to name
  String get displayHandle {
    if (channelHandle != null && channelHandle!.isNotEmpty) {
      return channelHandle!.startsWith('@') ? channelHandle! : '@$channelHandle';
    }
    return channelName;
  }

  /// Time since last check (for display)
  String get lastCheckedDisplay {
    if (lastChecked == null) return 'Not checked yet';

    final diff = DateTime.now().difference(lastChecked!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 30}mo ago';
  }

  /// Format latest video date
  String get latestVideoDateDisplay {
    if (latestVideoDate == null) return '';

    final diff = DateTime.now().difference(latestVideoDate!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7} weeks ago';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30} months ago';
    return '${diff.inDays ~/ 365} years ago';
  }
}
