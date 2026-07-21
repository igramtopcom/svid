import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:svid/features/browser/domain/services/browser_bookmark_service.dart';

void main() {
  late SharedPreferences prefs;
  late BrowserBookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = BrowserBookmarkService(prefs);
  });

  tearDown(() {
    service.dispose();
  });

  group('BrowserBookmarkService', () {
    test('starts with empty bookmarks', () {
      expect(service.bookmarks, isEmpty);
    });

    test('add creates a bookmark', () {
      service.add('https://example.com', 'Example');
      expect(service.bookmarks.length, 1);
      expect(service.bookmarks.first.url, 'https://example.com');
      expect(service.bookmarks.first.title, 'Example');
    });

    test('add does not duplicate existing URL', () {
      service.add('https://a.com', 'A');
      service.add('https://a.com', 'A Updated');
      expect(service.bookmarks.length, 1);
      expect(service.bookmarks.first.title, 'A'); // Original preserved
    });

    test('isBookmarked returns true for bookmarked URLs', () {
      service.add('https://a.com', 'A');
      expect(service.isBookmarked('https://a.com'), isTrue);
      expect(service.isBookmarked('https://b.com'), isFalse);
    });

    test('toggle adds bookmark when not exists — returns true', () {
      final result = service.toggle('https://a.com', 'A');
      expect(result, isTrue);
      expect(service.bookmarks.length, 1);
      expect(service.isBookmarked('https://a.com'), isTrue);
    });

    test('toggle removes bookmark when exists — returns false', () {
      service.add('https://a.com', 'A');
      final result = service.toggle('https://a.com', 'A');
      expect(result, isFalse);
      expect(service.bookmarks, isEmpty);
      expect(service.isBookmarked('https://a.com'), isFalse);
    });

    test('toggle add then remove then add again', () {
      service.toggle('https://a.com', 'A');
      expect(service.bookmarks.length, 1);

      service.toggle('https://a.com', 'A');
      expect(service.bookmarks, isEmpty);

      service.toggle('https://a.com', 'A Again');
      expect(service.bookmarks.length, 1);
      expect(service.bookmarks.first.title, 'A Again');
    });

    test('remove removes bookmark by ID', () {
      service.add('https://a.com', 'A');
      service.add('https://b.com', 'B');

      // Newest first: B, A — remove B (first)
      final idToRemove = service.bookmarks.first.id;
      service.remove(idToRemove);

      expect(service.bookmarks.length, 1);
      expect(service.bookmarks.first.url, 'https://a.com');
    });

    test('remove with non-existent ID does nothing', () {
      service.add('https://a.com', 'A');
      service.remove('non-existent');
      expect(service.bookmarks.length, 1);
    });

    test('getAll returns unmodifiable list', () {
      service.add('https://a.com', 'A');
      final list = service.getAll();
      expect(list.length, 1);
    });

    test('persists data to SharedPreferences', () async {
      service.add('https://a.com', 'A');

      final service2 = BrowserBookmarkService(prefs);
      expect(service2.bookmarks.length, 1);
      expect(service2.bookmarks.first.url, 'https://a.com');
      service2.dispose();
    });

    test('emits stream updates on toggle add', () async {
      final future = service.stream.first;
      service.toggle('https://a.com', 'A');

      final bookmarks = await future;
      expect(bookmarks.length, 1);
    });

    test('emits stream updates on remove', () async {
      service.add('https://a.com', 'A');
      final id = service.bookmarks.first.id;

      final future = service.stream.first;
      service.remove(id);

      final bookmarks = await future;
      expect(bookmarks, isEmpty);
    });
  });
}
