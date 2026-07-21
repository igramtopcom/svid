import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/browser/domain/services/browser_bookmark_service.dart';

void main() {
  late BrowserBookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = BrowserBookmarkService(prefs);
  });

  tearDown(() => service.dispose());

  // ── buildNetscapeHtml (top-level helper) ──────────────────────────────────

  group('buildNetscapeHtml', () {
    test('produces DOCTYPE NETSCAPE-Bookmark-file-1 header', () {
      final html = buildNetscapeHtml([]);
      expect(html, contains('<!DOCTYPE NETSCAPE-Bookmark-file-1>'));
    });

    test('empty bookmarks produces valid skeleton HTML', () {
      final html = buildNetscapeHtml([]);
      expect(html, contains('<DL><p>'));
      expect(html, contains('</DL><p>'));
    });

    test('contains each bookmark URL in an <A> tag', () {
      service.add('https://example.com', 'Example');
      service.add('https://flutter.dev', 'Flutter');
      final html = service.exportToNetscapeHtml();
      expect(html, contains('HREF="https://example.com"'));
      expect(html, contains('HREF="https://flutter.dev"'));
    });

    test('contains each bookmark title', () {
      service.add('https://example.com', 'My Example');
      final html = service.exportToNetscapeHtml();
      expect(html, contains('>My Example<'));
    });

    test('HTML-encodes special chars in title', () {
      service.add('https://example.com', 'A & B < C > D');
      final html = service.exportToNetscapeHtml();
      expect(html, contains('A &amp; B &lt; C &gt; D'));
    });
  });

  // ── parseNetscapeHtml (top-level helper) ──────────────────────────────────

  group('parseNetscapeHtml', () {
    test('returns empty list for empty HTML', () {
      expect(parseNetscapeHtml(''), isEmpty);
    });

    test('returns empty list for malformed HTML', () {
      expect(parseNetscapeHtml('not html at all'), isEmpty);
    });

    test('parses single <A> tag', () {
      const html =
          '<A HREF="https://example.com" ADD_DATE="0">Example</A>';
      final result = parseNetscapeHtml(html);
      expect(result.length, 1);
      expect(result.first.url, 'https://example.com');
      expect(result.first.title, 'Example');
    });

    test('decodes HTML entities in title', () {
      const html =
          '<A HREF="https://x.com">A &amp; B &lt; C &gt; D</A>';
      final result = parseNetscapeHtml(html);
      expect(result.first.title, 'A & B < C > D');
    });

    test('round-trip: export → parse returns same URLs', () {
      service.add('https://a.com', 'A');
      service.add('https://b.com', 'B');
      final html = service.exportToNetscapeHtml();
      final parsed = parseNetscapeHtml(html);
      final urls = parsed.map((e) => e.url).toSet();
      expect(urls, containsAll(['https://a.com', 'https://b.com']));
    });
  });

  // ── importFromNetscapeHtml ─────────────────────────────────────────────────

  group('BrowserBookmarkService.importFromNetscapeHtml', () {
    test('adds bookmarks from valid Netscape HTML', () {
      const html = '''<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
    <DT><A HREF="https://one.com" ADD_DATE="0">One</A>
    <DT><A HREF="https://two.com" ADD_DATE="0">Two</A>
</DL><p>''';
      final added = service.importFromNetscapeHtml(html);
      expect(added, 2);
      expect(service.bookmarks.length, 2);
    });

    test('does not add duplicate URLs', () {
      service.add('https://one.com', 'One');
      const html = '<A HREF="https://one.com">One</A>'
          '<A HREF="https://two.com">Two</A>';
      final added = service.importFromNetscapeHtml(html);
      expect(added, 1);
      expect(service.bookmarks.length, 2);
    });

    test('returns 0 for malformed HTML', () {
      final added = service.importFromNetscapeHtml('garbage <not html>');
      expect(added, 0);
    });
  });

  // ── exportToJson / importFromJson ─────────────────────────────────────────

  group('BrowserBookmarkService JSON export/import', () {
    test('exportToJson returns valid JSON array', () {
      service.add('https://a.com', 'A');
      final json = service.exportToJson();
      expect(json, startsWith('['));
      expect(json, contains('https://a.com'));
    });

    test('importFromJson round-trip', () async {
      service.add('https://x.com', 'X');
      service.add('https://y.com', 'Y');
      final json = service.exportToJson();

      // Fresh service
      SharedPreferences.setMockInitialValues({});
      final prefs2 = await SharedPreferences.getInstance();
      final service2 = BrowserBookmarkService(prefs2);
      addTearDown(service2.dispose);

      final added = service2.importFromJson(json);
      expect(added, 2);
      expect(service2.bookmarks.map((b) => b.url),
          containsAll(['https://x.com', 'https://y.com']));
    });

    test('importFromJson with invalid JSON returns 0', () {
      final added = service.importFromJson('{not valid json[');
      expect(added, 0);
    });

    test('importFromJson deduplicates by URL', () {
      service.add('https://x.com', 'X');
      final json = service.exportToJson();
      final added = service.importFromJson(json);
      expect(added, 0); // already exists
    });
  });
}
