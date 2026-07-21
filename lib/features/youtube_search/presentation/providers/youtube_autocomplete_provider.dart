import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/youtube_suggest_service.dart';

/// Provider for YouTubeSuggestService
final youtubeSuggestServiceProvider = Provider<YouTubeSuggestService>((ref) {
  final service = YouTubeSuggestService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// State for autocomplete suggestions
class AutocompleteState {
  final List<String> suggestions;
  final bool isLoading;
  final String? error;
  final String currentQuery;

  const AutocompleteState({
    this.suggestions = const [],
    this.isLoading = false,
    this.error,
    this.currentQuery = '',
  });

  AutocompleteState copyWith({
    List<String>? suggestions,
    bool? isLoading,
    String? error,
    String? currentQuery,
    bool clearError = false,
  }) {
    return AutocompleteState(
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }
}

/// Notifier for autocomplete suggestions with debouncing
class AutocompleteNotifier extends StateNotifier<AutocompleteState> {
  final YouTubeSuggestService _service;
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  AutocompleteNotifier(this._service) : super(const AutocompleteState());

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Fetch suggestions with debouncing
  void fetchSuggestions(String query) {
    // Cancel previous timer
    _debounceTimer?.cancel();

    final trimmed = query.trim();

    // Clear suggestions if query is empty
    if (trimmed.isEmpty) {
      state = const AutocompleteState();
      return;
    }

    // Set loading state immediately
    state = state.copyWith(
      isLoading: true,
      currentQuery: trimmed,
      clearError: true,
    );

    // Debounce API call
    _debounceTimer = Timer(_debounceDuration, () async {
      await _performFetch(trimmed);
    });
  }

  Future<void> _performFetch(String query) async {
    // Check if query is still current (user might have changed it)
    if (query != state.currentQuery) return;

    final result = await _service.getSuggestions(query);

    // Check again after async operation
    if (query != state.currentQuery) return;

    result.when(
      success: (suggestions) {
        state = state.copyWith(
          suggestions: suggestions,
          isLoading: false,
          clearError: true,
        );
      },
      failure: (exception) {
        state = state.copyWith(
          suggestions: [],
          isLoading: false,
          error: exception.toString(),
        );
      },
    );
  }

  /// Clear suggestions
  void clear() {
    _debounceTimer?.cancel();
    state = const AutocompleteState();
  }
}

/// Provider for autocomplete state
final youtubeAutocompleteProvider =
    StateNotifierProvider<AutocompleteNotifier, AutocompleteState>((ref) {
  final service = ref.watch(youtubeSuggestServiceProvider);
  return AutocompleteNotifier(service);
});
