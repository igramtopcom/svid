import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/browser/domain/entities/browser_bookmark.dart';
import 'package:svid/features/browser/domain/entities/browser_history_entry.dart';
import 'package:svid/features/browser/domain/services/address_bar_autocomplete_service.dart';

BrowserHistoryEntry _h(String url, {String title = ''}) => BrowserHistoryEntry(
      id: url,
      url: url,
      title: title,
      visitedAt: DateTime(2024),
    );

BrowserBookmark _b(String url, {String title = ''}) => BrowserBookmark(
      id: url,
      url: url,
      title: title,
      createdAt: DateTime(2024),
    );

void main() {
  late AddressBarAutocompleteService svc;

  setUp(() => svc = AddressBarAutocompleteService());

  // ── Query length guard ────────────────────────────────────────────────────
  test('returns empty list for empty query', () {
    expect(svc.suggest('', [_h('https://example.com')], []), isEmpty);
  });

  test('returns empty list for 1-char query', () {
    expect(svc.suggest('e', [_h('https://example.com')], []), isEmpty);
  });

  test('returns results for 2-char query', () {
    expect(
      svc.suggest('ex', [_h('https://example.com')], []),
      isNotEmpty,
    );
  });

  // ── Basic matching ────────────────────────────────────────────────────────
  test('matches URL containing query', () {
    final result = svc.suggest('you', [_h('https://youtube.com')], []);
    expect(result, hasLength(1));
    expect(result.first.url, 'https://youtube.com');
  });

  test('matches title containing query', () {
    final result = svc.suggest(
      'tube',
      [_h('https://youtube.com', title: 'YouTube - Broadcast Yourself')],
      [],
    );
    expect(result, isNotEmpty);
    expect(result.first.title, contains('YouTube'));
  });

  test('matching is case-insensitive', () {
    final result =
        svc.suggest('YOU', [_h('https://youtube.com', title: 'YouTube')], []);
    expect(result, isNotEmpty);
  });

  test('non-matching entries are excluded', () {
    final history = [_h('https://github.com'), _h('https://google.com')];
    final result = svc.suggest('github', history, []);
    expect(result, hasLength(1));
    expect(result.first.url, 'https://github.com');
  });

  // ── Ranking ───────────────────────────────────────────────────────────────
  test('URL-prefix match ranked above URL-contains match', () {
    final history = [
      _h('https://example-flutter-guide.com'),   // url contains 'flutter'
      _h('flutter.dev'),                          // url starts with 'flutter'
    ];
    final result = svc.suggest('flutter', history, []);
    expect(result.first.url, 'flutter.dev');
  });

  test('URL startsWith scores higher than URL contains', () {
    final history = [
      _h('https://a.com/not-here/youtube'),   // url contains 'youtube'
      _h('youtube.com'),                        // url startsWith 'youtube'
    ];
    final result = svc.suggest('youtube', history, []);
    expect(result.first.url, 'youtube.com');
  });

  test('title startsWith ranks above title contains', () {
    final history = [
      _h('https://a.com', title: 'see flutter docs'),  // title contains 'flutter'
      _h('https://b.com', title: 'Flutter official'),  // title startsWith 'flutter'
    ];
    final result = svc.suggest('flutter', history, []);
    expect(result.first.url, 'https://b.com');
  });

  // ── Bookmarks precede history ─────────────────────────────────────────────
  test('bookmarks come before history entries of equal score', () {
    final history = [_h('https://youtube.com/history')];
    final bookmarks = [_b('https://youtube.com/bookmark')];
    final result = svc.suggest('youtube', history, bookmarks);
    expect(result.first.isBookmark, isTrue);
  });

  test('bookmark results have isBookmark = true', () {
    final bookmarks = [_b('https://flutter.dev', title: 'Flutter')];
    final result = svc.suggest('flutter', [], bookmarks);
    expect(result.first.isBookmark, isTrue);
  });

  test('history results have isBookmark = false', () {
    final history = [_h('https://flutter.dev', title: 'Flutter')];
    final result = svc.suggest('flutter', history, []);
    expect(result.first.isBookmark, isFalse);
  });

  // ── Duplicate suppression ─────────────────────────────────────────────────
  test('history entry suppressed when same URL already in bookmarks', () {
    final url = 'https://flutter.dev';
    final history = [_h(url, title: 'Flutter')];
    final bookmarks = [_b(url, title: 'Flutter')];
    final result = svc.suggest('flutter', history, bookmarks);
    // Should only appear once (as bookmark)
    expect(result, hasLength(1));
    expect(result.first.isBookmark, isTrue);
  });

  // ── Max suggestions cap ───────────────────────────────────────────────────
  test('caps results at maxSuggestions (8)', () {
    final history = List.generate(
      20,
      (i) => _h('https://example$i.com', title: 'Example $i'),
    );
    final result = svc.suggest('example', history, []);
    expect(result.length, lessThanOrEqualTo(AddressBarAutocompleteService.maxSuggestions));
  });

  // ── Empty inputs ──────────────────────────────────────────────────────────
  test('returns empty list when no history or bookmarks match', () {
    final result = svc.suggest('zzz', [_h('https://example.com')], []);
    expect(result, isEmpty);
  });

  test('works with empty history and empty bookmarks', () {
    final result = svc.suggest('flutter', [], []);
    expect(result, isEmpty);
  });
}
