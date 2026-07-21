import 'package:dio/dio.dart';
import '../../../../../core/config/brand_config.dart';
import '../../../../../core/logging/app_logger.dart';
import '../../../../../core/network/dio_client.dart';
import '../dto/decode_response_dto.dart';
import '../dto/search_response_dto.dart';
import '../dto/youtube_search_convert_response_dto.dart';

/// API Service for video extraction backend (brand-aware)
class SSvidApiService {
  static String get _baseUrl => BrandConfig.current.extractionApiUrl;

  final Dio _dio = DioClient().dio;

  /// Search video metadata from URL
  ///
  /// @param url Source video URL (TikTok, Instagram, Facebook, Twitter, YouTube)
  /// @return SearchResponseDto with video metadata + ENCODED download tokens
  Future<SearchResponseDto> search(String url) async {
    appLogger.info('🔍 Searching URL');

    try {
      final response = await _dio.post(
        _baseUrl,
        data: FormData.fromMap({
          'action': 'search',
          'query': url,
        }),
      );

      final dto = SearchResponseDto.fromJson(response.data as Map<String, dynamic>);
      appLogger.info('✅ Search completed');
      return dto;
    } on DioException catch (e) {
      appLogger.error('⛔ Search failed', e);
      rethrow;
    }
  }

  /// Decodes an encrypted/encoded URL token to get a direct download URL
  ///
  /// @param encodedUrl The token from the search response
  /// @return DecodeResponseDto containing the direct download URL
  Future<DecodeResponseDto> decodeUrl(String encodedUrl) async {
    appLogger.info('🔓 Decoding URL');

    try {
      final response = await _dio.post(
        _baseUrl,
        data: FormData.fromMap({
          'action': 'decodeUrl',
          'urlendcode': encodedUrl,
        }),
      );

      final dto = DecodeResponseDto.fromJson(response.data as Map<String, dynamic>);
      appLogger.info('✅ Decode completed');
      return dto;
    } on DioException catch (e) {
      appLogger.error('⛔ Decode failed', e);
      rethrow;
    }
  }

  /// YouTube-specific search and convert API
  ///
  /// This endpoint initiates video conversion and returns conversion status.
  /// You need to poll this endpoint until c_status becomes "CONVERTED".
  ///
  /// @param videoId YouTube video ID (11 characters)
  /// @param qualityKey Conversion quality key (from initial search response)
  /// @return YouTubeSearchConvertResponseDto with conversion status
  Future<YouTubeSearchConvertResponseDto> searchConvert({
    required String videoId,
    required String qualityKey,
  }) async {
    appLogger.info('🎬 YouTube polling');

    try {
      final response = await _dio.post(
        _baseUrl,
        data: FormData.fromMap({
          'action': 'searchConvert',
          'vid': videoId,
          'key': qualityKey,
          'captcha_provider': 'turnstile',
        }),
      );

      final dto = YouTubeSearchConvertResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );

      if (dto.conversionStatus == 'CONVERTED') {
        appLogger.info('✅ YouTube conversion completed');
      }

      return dto;
    } on DioException catch (e) {
      appLogger.error('⛔ YouTube conversion failed', e);
      rethrow;
    }
  }
}
