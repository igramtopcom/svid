import 'package:freezed_annotation/freezed_annotation.dart';

import '../mixins/formatted_channel_mixin.dart';

part 'channel_info.freezed.dart';

@freezed
class ChannelInfo with _$ChannelInfo, FormattedChannelMixin {
  const ChannelInfo._();

  const factory ChannelInfo({
    required String id,
    required String title,
    String? uploader,
    String? uploaderId,
    String? thumbnail,
    String? description,
    int? subscriberCount,
    int? videoCount,
    required String webpageUrl,
  }) = _ChannelInfo;

  /// Get channel handle (@username) from URL or uploaderId
  String? get channelHandle {
    // Try to extract from URL first (e.g., https://www.youtube.com/@username)
    if (webpageUrl.contains('/@')) {
      final parts = webpageUrl.split('/@');
      if (parts.length > 1) {
        return '@${parts[1].split('/').first.split('?').first}';
      }
    }

    // Fallback to uploaderId if it exists
    if (uploaderId != null && uploaderId!.isNotEmpty) {
      return uploaderId!.startsWith('@') ? uploaderId : '@$uploaderId';
    }

    return null;
  }
}
