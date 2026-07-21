// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'youtube_search_convert_response_dto.freezed.dart';
part 'youtube_search_convert_response_dto.g.dart';

/// Response from YouTube searchConvert API
@freezed
class YouTubeSearchConvertResponseDto with _$YouTubeSearchConvertResponseDto {
  const factory YouTubeSearchConvertResponseDto({
    /// Status of the conversion: "CONVERTING" or "CONVERTED"
    @JsonKey(name: 'c_status') String? conversionStatus,

    /// Download link (available when c_status == "CONVERTED")
    @JsonKey(name: 'dlink') String? downloadLink,

    /// Batch ID for tracking conversion
    @JsonKey(name: 'b_id') String? batchId,

    /// Estimated time (NOT RELIABLE - don't trust this field)
    @JsonKey(name: 'e_time') int? estimatedTime,

    /// Available quality options with conversion keys
    @JsonKey(name: 'convert_links') List<YouTubeConvertLinkDto>? convertLinks,

    /// Title of the video
    String? title,

    /// Thumbnail URL
    String? thumbnail,

    /// Author information
    YouTubeAuthorDto? author,

    /// Duration in seconds
    int? duration,

    /// Error message if status is "error"
    String? error,

    /// Response status ("ok", "error", or empty)
    String? status,
  }) = _YouTubeSearchConvertResponseDto;

  factory YouTubeSearchConvertResponseDto.fromJson(Map<String, dynamic> json) =>
      _$YouTubeSearchConvertResponseDtoFromJson(json);
}

/// YouTube quality option with conversion key
@freezed
class YouTubeConvertLinkDto with _$YouTubeConvertLinkDto {
  const factory YouTubeConvertLinkDto({
    /// Conversion key to use for searchConvert polling
    required String key,

    /// Quality text (e.g., "1080p", "720p", "360p")
    required String quality,

    /// File size string (e.g., "45.2 MB")
    String? fsize,

    /// Format (e.g., "mp4", "webm")
    String? format,
  }) = _YouTubeConvertLinkDto;

  factory YouTubeConvertLinkDto.fromJson(Map<String, dynamic> json) =>
      _$YouTubeConvertLinkDtoFromJson(json);
}

/// YouTube author information
@freezed
class YouTubeAuthorDto with _$YouTubeAuthorDto {
  const factory YouTubeAuthorDto({
    String? username,
    @JsonKey(name: 'full_name') String? fullName,
    String? avatar,
  }) = _YouTubeAuthorDto;

  factory YouTubeAuthorDto.fromJson(Map<String, dynamic> json) =>
      _$YouTubeAuthorDtoFromJson(json);
}
