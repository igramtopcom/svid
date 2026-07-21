import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../youtube_search/presentation/providers/youtube_autocomplete_provider.dart';
import '../../domain/services/url_classifier_service.dart';

typedef HomeSuggestionFetcher =
    Future<Result<List<String>>> Function(String query);

@immutable
class HomeSearchSuggestionsState {
  final String query;
  final List<String> suggestions;
  final bool isLoading;
  final String? error;
  final bool onlineEligible;

  const HomeSearchSuggestionsState({
    this.query = '',
    this.suggestions = const [],
    this.isLoading = false,
    this.error,
    this.onlineEligible = false,
  });

  static const empty = HomeSearchSuggestionsState();

  HomeSearchSuggestionsState copyWith({
    String? query,
    List<String>? suggestions,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? onlineEligible,
  }) {
    return HomeSearchSuggestionsState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      onlineEligible: onlineEligible ?? this.onlineEligible,
    );
  }
}

class HomeSearchSuggestionsNotifier
    extends StateNotifier<HomeSearchSuggestionsState> {
  HomeSearchSuggestionsNotifier({
    required HomeSuggestionFetcher fetchSuggestions,
    UrlClassifierService? classifier,
    Duration debounce = const Duration(milliseconds: 300),
  }) : _fetchSuggestions = fetchSuggestions,
       _classifier = classifier ?? const UrlClassifierService(),
       _debounce = debounce,
       super(HomeSearchSuggestionsState.empty);

  final HomeSuggestionFetcher _fetchSuggestions;
  final UrlClassifierService _classifier;
  final Duration _debounce;
  Timer? _timer;

  static final RegExp _domainLikePattern = RegExp(
    r'(^|\s)([a-z0-9-]+\.)+(com|net|org|app|io|co|vn|tv|me|gg|ly|be|info|biz)([/\?#:]|$)',
    caseSensitive: false,
  );

  static bool shouldFetchOnlineSuggestions(
    String rawText,
    SmartInputType type,
  ) {
    final text = rawText.trim();
    if (type != SmartInputType.searchKeyword || text.length < 2) {
      return false;
    }
    return !looksLikeUrlFragment(text);
  }

  static bool looksLikeUrlFragment(String rawText) {
    final text = rawText.trim().toLowerCase();
    if (text.isEmpty) return false;
    if (text.contains('://') ||
        text.startsWith('http://') ||
        text.startsWith('https://')) {
      return true;
    }
    if (text.startsWith('www.') || text.contains(' www.')) return true;
    if (text.contains('watch?v=') || text.contains('playlist?list=')) {
      return true;
    }
    if (text.contains('youtube.com') || text.contains('youtu.be')) return true;
    return _domainLikePattern.hasMatch(text);
  }

  void updateQuery(String rawText) {
    _timer?.cancel();
    final query = rawText.trim();
    final type = _classifier.classify(query);
    final eligible = shouldFetchOnlineSuggestions(query, type);

    if (!eligible) {
      state = HomeSearchSuggestionsState(query: query, onlineEligible: false);
      return;
    }

    state = HomeSearchSuggestionsState(
      query: query,
      isLoading: true,
      onlineEligible: true,
    );

    _timer = Timer(_debounce, () async {
      await _performFetch(query);
    });
  }

  Future<void> _performFetch(String query) async {
    if (query != state.query || !state.onlineEligible) return;
    final result = await _fetchSuggestions(query);
    if (query != state.query || !state.onlineEligible) return;

    result.when(
      success: (suggestions) {
        state = state.copyWith(
          suggestions: suggestions.take(8).toList(growable: false),
          isLoading: false,
          clearError: true,
        );
      },
      failure: (exception) {
        state = state.copyWith(
          suggestions: const [],
          isLoading: false,
          error: exception.toString(),
        );
      },
    );
  }

  void clear() {
    _timer?.cancel();
    state = HomeSearchSuggestionsState.empty;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final homeSearchSuggestionsProvider = StateNotifierProvider.autoDispose<
  HomeSearchSuggestionsNotifier,
  HomeSearchSuggestionsState
>((ref) {
  final service = ref.watch(youtubeSuggestServiceProvider);
  return HomeSearchSuggestionsNotifier(
    fetchSuggestions: service.getSuggestions,
  );
});
