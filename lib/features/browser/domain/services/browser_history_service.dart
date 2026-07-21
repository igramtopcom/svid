import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../entities/browser_history_entry.dart';

/// Persists browsing history in SharedPreferences JSON.
/// Circular buffer with max 200 entries; de-duplicates by URL.
class BrowserHistoryService {
  static const String _storageKey = 'browser_history_data';
  static const int maxEntries = 200;
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  List<BrowserHistoryEntry> _entries = [];
  final StreamController<List<BrowserHistoryEntry>> _controller =
      StreamController<List<BrowserHistoryEntry>>.broadcast();

  BrowserHistoryService(this._prefs) {
    _load();
  }

  /// Current history entries (newest first)
  List<BrowserHistoryEntry> get entries => List.unmodifiable(_entries);

  /// Stream of history changes
  Stream<List<BrowserHistoryEntry>> get stream => _controller.stream;

  /// Add or update a history entry.
  /// If URL already exists, updates title and moves it to the top.
  /// When [isPrivate] is true the entry is silently dropped (incognito mode).
  void addEntry(String url, String title, {bool isPrivate = false}) {
    if (url.isEmpty || isPrivate) return;

    // De-duplicate: remove existing entry with same URL
    _entries.removeWhere((e) => e.url == url);

    final entry = BrowserHistoryEntry(
      id: _uuid.v4(),
      url: url,
      title: title,
      visitedAt: DateTime.now(),
    );

    _entries.insert(0, entry);

    // Circular buffer eviction
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }

    _save();
    _controller.add(entries);
  }

  /// Remove a single history entry by ID
  void remove(String id) {
    final removed = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    if (_entries.length != removed) {
      _save();
      _controller.add(entries);
    }
  }

  /// Clear all history
  void clearAll() {
    if (_entries.isEmpty) return;
    _entries = [];
    _save();
    _controller.add(entries);
  }

  /// Search history by title or URL (case-insensitive)
  List<BrowserHistoryEntry> search(String query) {
    if (query.isEmpty) return entries;
    final lower = query.toLowerCase();
    return _entries
        .where((e) =>
            e.title.toLowerCase().contains(lower) ||
            e.url.toLowerCase().contains(lower))
        .toList();
  }

  void _load() {
    final json = _prefs.getString(_storageKey);
    if (json == null) return;

    try {
      final list = jsonDecode(json) as List;
      _entries = list
          .map((e) => BrowserHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _entries = [];
    }
  }

  void _save() {
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    _prefs.setString(_storageKey, json);
  }

  void dispose() {
    _controller.close();
  }
}
