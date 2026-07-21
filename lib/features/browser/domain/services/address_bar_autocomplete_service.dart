import '../entities/browser_bookmark.dart';
import '../entities/browser_history_entry.dart';

/// A single autocomplete suggestion shown in the address bar dropdown.
class AutocompleteSuggestion {
  final String url;
  final String title;

  /// True when the suggestion originates from bookmarks (shows star icon).
  /// False when from browsing history (shows clock icon).
  final bool isBookmark;

  const AutocompleteSuggestion({
    required this.url,
    required this.title,
    required this.isBookmark,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutocompleteSuggestion &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          isBookmark == other.isBookmark;

  @override
  int get hashCode => Object.hash(url, isBookmark);
}

/// Pure-Dart service that merges + ranks browser history and bookmarks for
/// address bar autocomplete.
///
/// Ranking rules (highest score first):
///   4 — URL starts with query
///   3 — URL contains query
///   2 — Title starts with query
///   1 — Title contains query
///
/// Bookmarks precede history entries that share the same score tier.
/// Duplicate URLs from history are suppressed when a bookmark already covers them.
/// Results are capped at [maxSuggestions].
class AddressBarAutocompleteService {
  static const int maxSuggestions = 8;

  /// Returns up to [maxSuggestions] ranked suggestions for [query].
  ///
  /// Returns an empty list when [query] has fewer than 2 characters.
  List<AutocompleteSuggestion> suggest(
    String query,
    List<BrowserHistoryEntry> history,
    List<BrowserBookmark> bookmarks,
  ) {
    if (query.length < 2) return const [];

    final lower = query.toLowerCase();

    final bookmarkSuggestions = bookmarks
        .where((b) => _matches(b.url, b.title, lower))
        .map((b) =>
            AutocompleteSuggestion(url: b.url, title: b.title, isBookmark: true))
        .toList();

    // Suppress history entries whose URL is already covered by a bookmark.
    final bookmarkUrls = {for (final b in bookmarks) b.url};

    final historySuggestions = history
        .where((h) =>
            !bookmarkUrls.contains(h.url) && _matches(h.url, h.title, lower))
        .map((h) =>
            AutocompleteSuggestion(url: h.url, title: h.title, isBookmark: false))
        .toList();

    _sortByRelevance(bookmarkSuggestions, lower);
    _sortByRelevance(historySuggestions, lower);

    // Bookmarks before history, then cap.
    return [...bookmarkSuggestions, ...historySuggestions]
        .take(maxSuggestions)
        .toList();
  }

  bool _matches(String url, String title, String lower) =>
      url.toLowerCase().contains(lower) || title.toLowerCase().contains(lower);

  void _sortByRelevance(List<AutocompleteSuggestion> list, String lower) {
    list.sort((a, b) => _score(b, lower).compareTo(_score(a, lower)));
  }

  int _score(AutocompleteSuggestion s, String lower) {
    final url = s.url.toLowerCase();
    final title = s.title.toLowerCase();
    if (url.startsWith(lower)) return 4;
    if (url.contains(lower)) return 3;
    if (title.startsWith(lower)) return 2;
    if (title.contains(lower)) return 1;
    return 0;
  }
}
