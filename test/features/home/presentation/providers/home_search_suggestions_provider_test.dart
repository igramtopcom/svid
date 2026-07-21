import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/home/domain/services/url_classifier_service.dart';
import 'package:ssvid/features/home/presentation/providers/home_search_suggestions_provider.dart';

void main() {
  group('HomeSearchSuggestionsNotifier privacy guard', () {
    test('allows normal keyword suggestions', () {
      expect(
        HomeSearchSuggestionsNotifier.shouldFetchOnlineSuggestions(
          'lofi beats',
          SmartInputType.searchKeyword,
        ),
        isTrue,
      );
    });

    test('blocks short, non-keyword, and URL-like text', () {
      expect(
        HomeSearchSuggestionsNotifier.shouldFetchOnlineSuggestions(
          'a',
          SmartInputType.searchKeyword,
        ),
        isFalse,
      );
      expect(
        HomeSearchSuggestionsNotifier.shouldFetchOnlineSuggestions(
          'https://youtube.com/watch?v=abc',
          SmartInputType.singleVideo,
        ),
        isFalse,
      );
      expect(
        HomeSearchSuggestionsNotifier.looksLikeUrlFragment(
          'youtube.com/watch?v=abc',
        ),
        isTrue,
      );
      expect(
        HomeSearchSuggestionsNotifier.looksLikeUrlFragment('www.youtube.com'),
        isTrue,
      );
      expect(
        HomeSearchSuggestionsNotifier.looksLikeUrlFragment('watch?v=abc'),
        isTrue,
      );
    });
  });

  group('HomeSearchSuggestionsNotifier', () {
    test('fetches and stores suggestions after debounce', () async {
      final calls = <String>[];
      final notifier = HomeSearchSuggestionsNotifier(
        debounce: Duration.zero,
        fetchSuggestions: (query) async {
          calls.add(query);
          return const Result.success(['lofi hip hop', 'lofi girl']);
        },
      );
      addTearDown(notifier.dispose);

      notifier.updateQuery('lofi');
      expect(notifier.state.isLoading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(calls, ['lofi']);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.suggestions, ['lofi hip hop', 'lofi girl']);
    });

    test('does not call online fetcher for URL-like fragments', () async {
      final calls = <String>[];
      final notifier = HomeSearchSuggestionsNotifier(
        debounce: Duration.zero,
        fetchSuggestions: (query) async {
          calls.add(query);
          return const Result.success(['should not fetch']);
        },
      );
      addTearDown(notifier.dispose);

      notifier.updateQuery('youtube.com/watch?v=abc');
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(calls, isEmpty);
      expect(notifier.state.onlineEligible, isFalse);
      expect(notifier.state.suggestions, isEmpty);
    });
  });
}
