import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../settings/domain/enums/download_engine.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/download_referer_holder.dart';
import '../../domain/usecases/extract_video_info_usecase.dart';
import 'download_providers.dart';

/// Extraction state - persists across navigation
class ExtractionState {
  final bool isExtracting;
  final String? extractingUrl;
  final VideoInfo? pendingVideoInfo;
  final String? error;
  final String? cookiesFile;
  final DateTime? startedAt;

  const ExtractionState({
    this.isExtracting = false,
    this.extractingUrl,
    this.pendingVideoInfo,
    this.error,
    this.cookiesFile,
    this.startedAt,
  });

  ExtractionState copyWith({
    bool? isExtracting,
    String? extractingUrl,
    VideoInfo? pendingVideoInfo,
    String? error,
    String? cookiesFile,
    DateTime? startedAt,
    bool clearPendingVideoInfo = false,
    bool clearError = false,
    bool clearExtractingUrl = false,
    bool clearStartedAt = false,
  }) {
    return ExtractionState(
      isExtracting: isExtracting ?? this.isExtracting,
      extractingUrl:
          clearExtractingUrl ? null : (extractingUrl ?? this.extractingUrl),
      pendingVideoInfo:
          clearPendingVideoInfo
              ? null
              : (pendingVideoInfo ?? this.pendingVideoInfo),
      error: clearError ? null : (error ?? this.error),
      cookiesFile: cookiesFile ?? this.cookiesFile,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
    );
  }

  bool get hasPendingResult => pendingVideoInfo != null;
  bool get hasError => error != null;
}

/// Global extraction state notifier
/// Manages extraction lifecycle independently of widget lifecycle
class ExtractionNotifier extends StateNotifier<ExtractionState> {
  final ExtractVideoInfoUseCase _extractUseCase;
  int _extractionGeneration = 0;

  ExtractionNotifier(this._extractUseCase) : super(const ExtractionState());

  /// Start extraction in background
  /// Returns immediately, result will be available in state
  Future<void> startExtraction({
    required String url,
    required DownloadEngine engine,
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    bool stopOnLoginRequired = false,
  }) async {
    // Don't start if already extracting
    if (state.isExtracting) {
      appLogger.warning('Extraction already in progress, ignoring new request');
      return;
    }

    final generation = ++_extractionGeneration;

    // Clear previous state and start new extraction
    state = ExtractionState(
      isExtracting: true,
      extractingUrl: url,
      cookiesFile: cookiesFile,
      startedAt: DateTime.now(),
    );

    appLogger.info('🚀 [Extraction] Starting background extraction: $url');

    try {
      final result = await _extractUseCase(
        url,
        engine: engine,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: cookiesFromBrowserFallback,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        proxyUrl: proxyUrl,
        stopOnLoginRequired: stopOnLoginRequired,
      );

      // Extraction was cancelled or superseded while awaiting — discard result
      if (generation != _extractionGeneration) return;

      result.when(
        success: (videoInfo) {
          // Browser-sniffed HLS: extraction ran on the raw manifest, so
          // yt-dlp's title is the playlist filename ("master"/"index").
          // Replace it with the page title stamped by the sniff panel.
          final stampedTitle = DownloadRefererHolder.lookupTitle(url);
          final effectiveInfo =
              (stampedTitle != null && stampedTitle.trim().isNotEmpty)
                  ? videoInfo.copyWith(title: stampedTitle.trim())
                  : videoInfo;
          appLogger.info('✅ [Extraction] Completed: ${effectiveInfo.title}');
          state = state.copyWith(
            isExtracting: false,
            pendingVideoInfo: effectiveInfo,
            clearError: true,
          );
        },
        failure: (exception) {
          final errorMessage =
              exception is AppException
                  ? exception.message
                  : exception.toString();
          appLogger.error('❌ [Extraction] Failed: $errorMessage');
          state = state.copyWith(
            isExtracting: false,
            error: errorMessage,
            // Keep extractingUrl so auto-login can retry with cookies
          );
        },
      );
    } catch (e, stack) {
      if (generation != _extractionGeneration) return;
      appLogger.error('❌ [Extraction] Unexpected error', e, stack);
      state = state.copyWith(
        isExtracting: false,
        error: AppExceptionX.readableMessage(e),
        // Keep extractingUrl so auto-login can retry with cookies
      );
    }
  }

  /// Atomically consume the pending video info.
  /// Returns the VideoInfo if available, null if already consumed.
  /// This prevents duplicate dialog display when multiple listeners fire
  /// (e.g., home_screen and browser_screen both listening to extractionProvider).
  VideoInfo? consumePendingResult() {
    final videoInfo = state.pendingVideoInfo;
    if (videoInfo == null) return null;
    state = state.copyWith(
      clearPendingVideoInfo: true,
      clearExtractingUrl: true,
      clearError: true,
      clearStartedAt: true,
    );
    return videoInfo;
  }

  /// Clear pending video info after user handles it (download or cancel)
  void clearPendingResult() {
    state = state.copyWith(
      clearPendingVideoInfo: true,
      clearExtractingUrl: true,
      clearError: true,
      clearStartedAt: true,
    );
  }

  /// Clear error after user dismisses it
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Cancel ongoing extraction (if possible)
  void cancelExtraction() {
    if (state.isExtracting) {
      appLogger.info('🛑 [Extraction] Cancelled by user');
      _extractionGeneration++; // Invalidate the running extraction's callback
      state = const ExtractionState();
    }
  }
}

/// Provider for extraction state
final extractionProvider =
    StateNotifierProvider<ExtractionNotifier, ExtractionState>((ref) {
      final extractUseCase = ref.watch(extractVideoInfoUseCaseProvider);
      return ExtractionNotifier(extractUseCase);
    });

/// Convenience provider to check if extracting
final isExtractingProvider = Provider<bool>((ref) {
  return ref.watch(extractionProvider).isExtracting;
});

/// Convenience provider to get pending video info
final pendingVideoInfoProvider = Provider<VideoInfo?>((ref) {
  return ref.watch(extractionProvider).pendingVideoInfo;
});
