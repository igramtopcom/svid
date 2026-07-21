// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_response_dto.freezed.dart';
part 'search_response_dto.g.dart';

@freezed
class SearchResponseDto with _$SearchResponseDto {
  const factory SearchResponseDto({
    String? status,
    SearchDataDto? data,
    String? error,
  }) = _SearchResponseDto;

  factory SearchResponseDto.fromJson(Map<String, dynamic> json) =>
      _$SearchResponseDtoFromJson(json);
}

@freezed
class SearchDataDto with _$SearchDataDto {
  const factory SearchDataDto({
    String? page,
    String? extractor,
    @JsonKey(name: 'status') String? statusText,
    String? keyword,
    required String title,
    String? thumbnail,
    @JsonKey(fromJson: _linksFromJson) LinksDto? links,
    @JsonKey(name: 'convert_links', fromJson: _convertLinksFromJson) ConvertLinksWrapperDto? convertLinks,
    @JsonKey(fromJson: _authorFromJson) AuthorDto? author,
    @JsonKey(fromJson: _galleryFromJson) GalleryDto? gallery,
    int? duration,
  }) = _SearchDataDto;

  factory SearchDataDto.fromJson(Map<String, dynamic> json) =>
      _$SearchDataDtoFromJson(json);
}

// Custom field converters to handle API inconsistencies
// Based on iOS NetworkModels.swift:109-129 (handles array AND dictionary formats)
LinksDto? _linksFromJson(dynamic json) {
  if (json is String || json == null) return null;

  if (json is Map<String, dynamic>) {
    final links = Map<String, dynamic>.from(json);

    // Handle video field - can be List, Map (single object), or Dictionary {String: VideoLinkDto}
    if (links['video'] is String || links['video'] == null) {
      links['video'] = null;
    } else if (links['video'] is List) {
      // Already a list - keep as is
      links['video'] = links['video'];
    } else if (links['video'] is Map) {
      final videoMap = links['video'] as Map<String, dynamic>;
      // Check if it's a single VideoLinkDto object (has 'url' or 'q_text' field)
      if (videoMap.containsKey('url') || videoMap.containsKey('q_text')) {
        // Single object - wrap in list
        links['video'] = [videoMap];
      } else {
        // Dictionary format {String: VideoLinkDto} - extract values
        links['video'] = videoMap.values.toList();
      }
    }

    // Handle audio field - same logic as video
    if (links['audio'] is String || links['audio'] == null) {
      links['audio'] = null;
    } else if (links['audio'] is List) {
      // Already a list - keep as is
      links['audio'] = links['audio'];
    } else if (links['audio'] is Map) {
      final audioMap = links['audio'] as Map<String, dynamic>;
      // Check if it's a single AudioLinkDto object
      if (audioMap.containsKey('url') || audioMap.containsKey('q_text')) {
        // Single object - wrap in list
        links['audio'] = [audioMap];
      } else {
        // Dictionary format {String: AudioLinkDto} - extract values
        links['audio'] = audioMap.values.toList();
      }
    }

    return LinksDto.fromJson(links);
  }

  return null;
}

ConvertLinksWrapperDto? _convertLinksFromJson(dynamic json) {
  if (json is String || json == null) return null;
  if (json is Map<String, dynamic>) return ConvertLinksWrapperDto.fromJson(json);
  return null;
}

AuthorDto? _authorFromJson(dynamic json) {
  if (json is String || json == null) return null;
  if (json is Map<String, dynamic>) return AuthorDto.fromJson(json);
  return null;
}

GalleryDto? _galleryFromJson(dynamic json) {
  if (json is String || json == null) return null;
  if (json is Map<String, dynamic>) return GalleryDto.fromJson(json);
  return null;
}

@freezed
class LinksDto with _$LinksDto {
  const factory LinksDto({
    List<VideoLinkDto>? video,
    List<AudioLinkDto>? audio,
  }) = _LinksDto;

  factory LinksDto.fromJson(Map<String, dynamic> json) =>
      _$LinksDtoFromJson(json);
}

@freezed
class VideoLinkDto with _$VideoLinkDto {
  const factory VideoLinkDto({
    @JsonKey(name: 'q_text', fromJson: _qualityTextFromJson) required String qualityText,
    @JsonKey(fromJson: _sizeFromJson) required String size,
    @JsonKey(name: 'url', fromJson: _encryptedUrlFromJson) required String encryptedUrl,
  }) = _VideoLinkDto;

  factory VideoLinkDto.fromJson(Map<String, dynamic> json) =>
      _$VideoLinkDtoFromJson(json);
}

@freezed
class AudioLinkDto with _$AudioLinkDto {
  const factory AudioLinkDto({
    @JsonKey(name: 'q_text', fromJson: _qualityTextFromJson) required String qualityText,
    @JsonKey(fromJson: _sizeFromJson) required String size,
    @JsonKey(name: 'url', fromJson: _encryptedUrlFromJson) required String encryptedUrl,
  }) = _AudioLinkDto;

  factory AudioLinkDto.fromJson(Map<String, dynamic> json) =>
      _$AudioLinkDtoFromJson(json);
}

// Based on iOS NetworkModels.swift:146-178 - fallback logic for missing fields
String _qualityTextFromJson(dynamic json) {
  if (json is String && json.isNotEmpty) return json;
  // Fallback to "Unknown" like iOS
  return 'Unknown';
}

String _sizeFromJson(dynamic json) {
  if (json is String) return json;
  if (json is int) return json == 0 ? '' : '$json';
  // Fallback to empty string like iOS
  return '';
}

String _encryptedUrlFromJson(dynamic json) {
  if (json is String && json.isNotEmpty) return json;
  // iOS throws error here, but we'll return empty to avoid crash
  // Let mapper layer filter it out
  return '';
}

@freezed
class ConvertLinkDto with _$ConvertLinkDto {
  const factory ConvertLinkDto({
    required String key,
    required String quality,
    String? fsize,
    String? format,
  }) = _ConvertLinkDto;

  factory ConvertLinkDto.fromJson(Map<String, dynamic> json) =>
      _$ConvertLinkDtoFromJson(json);
}

@freezed
class ConvertLinksWrapperDto with _$ConvertLinksWrapperDto {
  const factory ConvertLinksWrapperDto({
    List<ConvertLinkDto>? video,
    List<ConvertLinkDto>? audio,
  }) = _ConvertLinksWrapperDto;

  factory ConvertLinksWrapperDto.fromJson(Map<String, dynamic> json) =>
      _$ConvertLinksWrapperDtoFromJson(json);
}

@freezed
class AuthorDto with _$AuthorDto {
  const factory AuthorDto({
    required String username,
    @JsonKey(name: 'full_name') String? fullName,
    String? avatar,
  }) = _AuthorDto;

  factory AuthorDto.fromJson(Map<String, dynamic> json) =>
      _$AuthorDtoFromJson(json);
}

@freezed
class GalleryDto with _$GalleryDto {
  const factory GalleryDto({
    List<GalleryItemDto>? items,
  }) = _GalleryDto;

  factory GalleryDto.fromJson(Map<String, dynamic> json) =>
      _$GalleryDtoFromJson(json);
}

@freezed
class GalleryItemDto with _$GalleryItemDto {
  const factory GalleryItemDto({
    String? id,
    @JsonKey(name: 'ftype') String? fileType,
    @JsonKey(name: 'thumb') String? thumbnail,
    String? label,
    List<ResourceDto>? resources,
  }) = _GalleryItemDto;

  factory GalleryItemDto.fromJson(Map<String, dynamic> json) =>
      _$GalleryItemDtoFromJson(json);
}

@freezed
class ResourceDto with _$ResourceDto {
  const factory ResourceDto({
    String? fsize,
    @JsonKey(name: 'src') required String encryptedUrl,
  }) = _ResourceDto;

  factory ResourceDto.fromJson(Map<String, dynamic> json) =>
      _$ResourceDtoFromJson(json);
}
