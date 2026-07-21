import 'package:dio/dio.dart';
import '../logging/app_logger.dart';

/// Configured Dio client for HTTP requests
class DioClient {
  static final DioClient _instance = DioClient._internal();

  factory DioClient() => _instance;

  late final Dio _dio;

  DioClient._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'accept': 'application/json, text/javascript, */*; q=0.01',
        'accept-language': 'en-US,en;q=0.9',
        'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'x-requested-with': 'XMLHttpRequest',
      },
    ));

    // Add interceptor for error logging only (reduces verbosity)
    // In release mode, only log errors. In debug mode, log minimal info.
    _dio.interceptors.add(LogInterceptor(
      request: false, // Don't log request details
      requestHeader: false, // Don't log request headers
      requestBody: false, // Don't log request body
      responseHeader: false, // Don't log response headers
      responseBody: false, // Don't log response body
      error: true, // Log errors only
      logPrint: (object) => appLogger.debug(object.toString()),
    ));
  }

  Dio get dio => _dio;
}
