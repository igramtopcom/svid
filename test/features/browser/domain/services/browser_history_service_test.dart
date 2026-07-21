import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ssvid/features/browser/domain/services/browser_history_service.dart';

void main() {
  late SharedPreferences prefs;
  late BrowserHistoryService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = BrowserHistoryService(prefs);
  });

  tearDown(() {
    service.dispose();
  });

  group('BrowserHistoryService', () {
    test('starts with empty entries', () {
      expect(service.entries, isEmpty);
    });

    test('addEntry adds entry to the top', () {
      service.addEntry('https://example.com', 'Example');
      expect(service.entries.length, 1);
      expect(service.entries.first.url, 'https://example.com');
      expect(service.entries.first.title, 'Example');
    });

    test('addEntry de-duplicates by URL — moves to top', () {
      service.addEntry('https://a.com', 'A');
      service.addEntry('https://b.com', 'B');
      service.addEntry('https://a.com', 'A Updated');

      expect(service.entries.length, 2);
      expect(service.entries.first.url, 'https://a.com');
      expect(service.entries.first.title, 'A Updated');
      expect(service.entries.last.url, 'https://b.com');
    });

    test('addEntry ignores empty URL', () {
      service.addEntry('', 'Empty');
      expect(service.entries, isEmpty);
    });

    test('addEntry enforces max 200 entries', () {
      for (int i = 0; i < 210; i++) {
        service.addEntry('https://site$i.com', 'Site $i');
      }

      expect(service.entries.length, BrowserHistoryService.maxEntries);
      // Newest should be first
      expect(service.entries.first.url, 'https://site209.com');
    });

    test('remove removes entry by ID', () {
      service.addEntry('https://a.com', 'A');
      service.addEntry('https://b.com', 'B');

      final idToRemove = service.entries.last.id;
      service.remove(idToRemove);

      expect(service.entries.length, 1);
      expect(service.entries.first.url, 'https://b.com');
    });

    test('remove with non-existent ID does nothing', () {
      service.addEntry('https://a.com', 'A');
      service.remove('non-existent');
      expect(service.entries.length, 1);
    });

    test('clearAll removes all entries', () {
      service.addEntry('https://a.com', 'A');
      service.addEntry('https://b.com', 'B');
      service.clearAll();
      expect(service.entries, isEmpty);
    });

    test('clearAll on empty list does nothing', () {
      service.clearAll(); // Should not throw
      expect(service.entries, isEmpty);
    });

    test('search by title (case-insensitive)', () {
      service.addEntry('https://a.com', 'Flutter Tutorial');
      service.addEntry('https://b.com', 'Dart Guide');
      service.addEntry('https://c.com', 'React Guide');

      final results = service.search('flutter');
      expect(results.length, 1);
      expect(results.first.title, 'Flutter Tutorial');
    });

    test('search by URL', () {
      service.addEntry('https://flutter.dev', 'Flutter');
      service.addEntry('https://dart.dev', 'Dart');

      final results = service.search('dart.dev');
      expect(results.length, 1);
      expect(results.first.url, 'https://dart.dev');
    });

    test('search with empty query returns all', () {
      service.addEntry('https://a.com', 'A');
      service.addEntry('https://b.com', 'B');

      final results = service.search('');
      expect(results.length, 2);
    });

    test('persists data to SharedPreferences', () async {
      service.addEntry('https://a.com', 'A');

      // Create a new service from same prefs
      final service2 = BrowserHistoryService(prefs);
      expect(service2.entries.length, 1);
      expect(service2.entries.first.url, 'https://a.com');
      service2.dispose();
    });

    test('emits stream updates on addEntry', () async {
      final future = service.stream.first;
      service.addEntry('https://a.com', 'A');

      final entries = await future;
      expect(entries.length, 1);
      expect(entries.first.url, 'https://a.com');
    });

    test('emits stream updates on clearAll', () async {
      service.addEntry('https://a.com', 'A');

      final future = service.stream.first;
      service.clearAll();

      final entries = await future;
      expect(entries, isEmpty);
    });
  });
}
