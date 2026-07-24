import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../entities/browser_bookmark.dart';

// ─── Netscape HTML helpers (top-level, @visibleForTesting) ───────────────────

/// Generates a Netscape Bookmarks HTML string from [bookmarks].
/// Compatible with Chrome/Firefox/Safari importers.
String buildNetscapeHtml(List<BrowserBookmark> bookmarks) {
  final buf = StringBuffer()
    ..writeln('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
    ..writeln(
        '<!-- This is an automatically generated file. Do not edit! -->')
    ..writeln('<META HTTP-EQUIV="Content-Type" '
        'CONTENT="text/html; charset=UTF-8">')
    ..writeln('<TITLE>Bookmarks</TITLE>')
    ..writeln('<H1>Bookmarks</H1>')
    ..writeln('<DL><p>');

  for (final b in bookmarks) {
    final addDate =
        (b.createdAt.millisecondsSinceEpoch ~/ 1000).toString();
    final escaped = b.title
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    buf.writeln(
        '    <DT><A HREF="${b.url}" ADD_DATE="$addDate">$escaped</A>');
  }

  buf.writeln('</DL><p>');
  return buf.toString();
}

/// Parses a Netscape Bookmarks HTML string and returns extracted entries.
/// Returns an empty list on parse failure — never throws.
List<({String url, String title})> parseNetscapeHtml(String html) {
  final results = <({String url, String title})>[];
  final pattern = RegExp(
    r'''<A\s+[^>]*HREF="([^"]+)"[^>]*>([^<]*)</A>''',
    caseSensitive: false,
  );
  for (final m in pattern.allMatches(html)) {
    final url = m.group(1)?.trim() ?? '';
    final rawTitle = m.group(2)?.trim() ?? '';
    final title = rawTitle
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    if (url.isNotEmpty) results.add((url: url, title: title));
  }
  return results;
}

/// Persists browser bookmarks in SharedPreferences JSON.
class BrowserBookmarkService {
  static const String _storageKey = 'browser_bookmarks_data';
  static const String _seededKey = 'browser_bookmarks_seeded_v1';
  // One-time removal of the YouTube homepage that older builds auto-seeded —
  // YouTube can't be sniffed in-browser, so it no longer belongs in defaults.
  static const String _ytDeseedKey = 'browser_bookmarks_yt_deseed_v1';
  // One-time removal of the copyright-heavy default seeds (FB/IG/X/…) that
  // older builds shipped — those sites host mostly rights-protected video, so
  // only Bilibili remains a default.
  static const String _copyrightDeseedKey =
      'browser_bookmarks_copyright_deseed_v1';
  static const _uuid = Uuid();

  /// Seeded on first run so the new-tab page starts with one useful example.
  /// Kept intentionally minimal — most social/video platforms host
  /// rights-protected content, so we don't pre-populate them; users add their
  /// own sites. (TikTok crashes WebView2; YouTube can't be sniffed in-browser.)
  static const List<({String url, String title})> defaultSeeds = [
    (url: 'https://www.bilibili.com', title: 'Bilibili'),
  ];

  /// Default seeds older builds shipped that are now removed on upgrade (only
  /// the exact seed URLs — a user's own bookmark of these sites is untouched).
  static const List<String> _retiredSeedUrls = [
    'https://www.facebook.com',
    'https://www.instagram.com',
    'https://x.com',
    'https://www.reddit.com',
    'https://vimeo.com',
    'https://www.dailymotion.com',
    'https://www.twitch.tv',
    'https://soundcloud.com',
    'https://www.pinterest.com',
  ];

  final SharedPreferences _prefs;
  List<BrowserBookmark> _bookmarks = [];
  final StreamController<List<BrowserBookmark>> _controller =
      StreamController<List<BrowserBookmark>>.broadcast();

  BrowserBookmarkService(this._prefs) {
    _load();
    _seedDefaultsIfFirstRun();
    _removeSeededYouTubeOnce();
    _removeRetiredSeedsOnce();
  }

  /// Removes the retired default seeds exactly once (migration). Only the exact
  /// seed URLs are targeted, so a user's own bookmark of these sites survives.
  void _removeRetiredSeedsOnce() {
    if (_prefs.getBool(_copyrightDeseedKey) ?? false) return;
    _prefs.setBool(_copyrightDeseedKey, true);
    final before = _bookmarks.length;
    final retired = _retiredSeedUrls
        .map((u) => u.toLowerCase().replaceAll(RegExp(r'/$'), ''))
        .toSet();
    _bookmarks.removeWhere(
      (b) => retired.contains(
        b.url.toLowerCase().replaceAll(RegExp(r'/$'), ''),
      ),
    );
    if (_bookmarks.length != before) {
      _save();
      _controller.add(bookmarks);
    }
  }

  /// Removes the auto-seeded YouTube homepage exactly once (migration). Only the
  /// exact default URL is targeted, so a user's own YouTube video/channel
  /// bookmarks are never touched.
  void _removeSeededYouTubeOnce() {
    if (_prefs.getBool(_ytDeseedKey) ?? false) return;
    _prefs.setBool(_ytDeseedKey, true);
    final before = _bookmarks.length;
    _bookmarks.removeWhere((b) {
      final u = b.url.toLowerCase().replaceAll(RegExp(r'/$'), '');
      return u == 'https://www.youtube.com' || u == 'https://youtube.com';
    });
    if (_bookmarks.length != before) {
      _save();
      _controller.add(bookmarks);
    }
  }

  /// Seeds [defaultSeeds] exactly once (first run). Guarded by a prefs flag so
  /// that a user who removes the defaults doesn't get them back on next launch.
  void _seedDefaultsIfFirstRun() {
    if (_prefs.getBool(_seededKey) ?? false) return;
    for (final s in defaultSeeds) {
      if (_bookmarks.any((b) => b.url == s.url)) continue;
      // Append (not insert) so YouTube stays first in the grid.
      _bookmarks.add(
        BrowserBookmark(
          id: _uuid.v4(),
          url: s.url,
          title: s.title,
          createdAt: DateTime.now(),
        ),
      );
    }
    _prefs.setBool(_seededKey, true);
    _save();
  }

  /// Current bookmarks (newest first)
  List<BrowserBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  /// Stream of bookmark changes
  Stream<List<BrowserBookmark>> get stream => _controller.stream;

  /// Check if a URL is bookmarked
  bool isBookmarked(String url) {
    return _bookmarks.any((b) => b.url == url);
  }

  /// Toggle bookmark for a URL. Returns true if added, false if removed.
  bool toggle(String url, String title) {
    final existing = _bookmarks.indexWhere((b) => b.url == url);
    if (existing >= 0) {
      _bookmarks.removeAt(existing);
      _save();
      _controller.add(bookmarks);
      return false;
    } else {
      final bookmark = BrowserBookmark(
        id: _uuid.v4(),
        url: url,
        title: title,
        createdAt: DateTime.now(),
      );
      _bookmarks.insert(0, bookmark);
      _save();
      _controller.add(bookmarks);
      return true;
    }
  }

  /// Add a bookmark
  void add(String url, String title) {
    if (isBookmarked(url)) return;
    final bookmark = BrowserBookmark(
      id: _uuid.v4(),
      url: url,
      title: title,
      createdAt: DateTime.now(),
    );
    _bookmarks.insert(0, bookmark);
    _save();
    _controller.add(bookmarks);
  }

  /// Remove a bookmark by ID
  void remove(String id) {
    final removed = _bookmarks.length;
    _bookmarks.removeWhere((b) => b.id == id);
    if (_bookmarks.length != removed) {
      _save();
      _controller.add(bookmarks);
    }
  }

  /// Get all bookmarks
  List<BrowserBookmark> getAll() => bookmarks;

  // ─── Export ────────────────────────────────────────────────────────────────

  /// Exports all bookmarks as a Netscape Bookmarks HTML string.
  String exportToNetscapeHtml() => buildNetscapeHtml(_bookmarks);

  /// Exports all bookmarks as a JSON string (Svid backup format).
  String exportToJson() =>
      jsonEncode(_bookmarks.map((b) => b.toJson()).toList());

  // ─── Import ────────────────────────────────────────────────────────────────

  /// Imports bookmarks from a Netscape HTML string.
  /// Deduplicates by URL (existing bookmarks are not replaced).
  /// Returns the number of new bookmarks added.
  int importFromNetscapeHtml(String html) {
    final parsed = parseNetscapeHtml(html);
    var added = 0;
    for (final entry in parsed) {
      if (!isBookmarked(entry.url)) {
        _bookmarks.add(BrowserBookmark(
          id: _uuid.v4(),
          url: entry.url,
          title: entry.title.isNotEmpty ? entry.title : entry.url,
          createdAt: DateTime.now(),
        ));
        added++;
      }
    }
    if (added > 0) {
      _save();
      _controller.add(bookmarks);
    }
    return added;
  }

  /// Imports bookmarks from a JSON string (Svid backup format).
  /// Deduplicates by URL.
  /// Returns the number of new bookmarks added.
  int importFromJson(String json) {
    try {
      final list = jsonDecode(json) as List;
      var added = 0;
      for (final item in list) {
        final b = BrowserBookmark.fromJson(item as Map<String, dynamic>);
        if (!isBookmarked(b.url)) {
          _bookmarks.add(BrowserBookmark(
            id: _uuid.v4(),
            url: b.url,
            title: b.title,
            createdAt: b.createdAt,
          ));
          added++;
        }
      }
      if (added > 0) {
        _save();
        _controller.add(bookmarks);
      }
      return added;
    } catch (_) {
      return 0;
    }
  }

  void _load() {
    final json = _prefs.getString(_storageKey);
    if (json == null) return;

    try {
      final list = jsonDecode(json) as List;
      _bookmarks = list
          .map((e) => BrowserBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _bookmarks = [];
    }
  }

  void _save() {
    final json = jsonEncode(_bookmarks.map((b) => b.toJson()).toList());
    _prefs.setString(_storageKey, json);
  }

  void dispose() {
    _controller.close();
  }
}
