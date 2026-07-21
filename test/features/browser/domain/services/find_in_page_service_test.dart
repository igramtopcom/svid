import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/browser/domain/services/find_in_page_service.dart';

void main() {
  late FindInPageService service;

  setUp(() {
    service = FindInPageService();
  });

  group('escapeJs', () {
    test('escapes single quotes', () {
      expect(FindInPageService.escapeJs("it's"), r"it\'s");
    });

    test('escapes double quotes', () {
      expect(FindInPageService.escapeJs('say "hi"'), r'say \"hi\"');
    });

    test('escapes backslashes', () {
      expect(FindInPageService.escapeJs(r'path\to'), r'path\\to');
    });

    test('escapes newlines and tabs', () {
      expect(FindInPageService.escapeJs('a\nb\tc'), r'a\nb\tc');
    });

    test('handles empty string', () {
      expect(FindInPageService.escapeJs(''), '');
    });

    test('handles carriage return', () {
      expect(FindInPageService.escapeJs('a\rb'), r'a\rb');
    });
  });

  group('generateFindScript', () {
    test('returns clear script for empty query', () {
      final script = service.generateFindScript('');
      expect(script, contains('querySelectorAll'));
      expect(script, contains('-find-highlight'));
      // Should be the clear script
      expect(script, isNot(contains('TreeWalker')));
    });

    test('generates script with query text', () {
      final script = service.generateFindScript('hello');
      expect(script, contains('hello'));
      expect(script, contains('-find-highlight'));
      expect(script, contains('totalMatches'));
    });

    test('uses case-insensitive flag by default', () {
      final script = service.generateFindScript('test');
      expect(script, contains("'gi'"));
    });

    test('uses no flags when caseSensitive is true', () {
      final script =
          service.generateFindScript('test', caseSensitive: true);
      // With caseSensitive=true, flags should be empty string
      expect(script, contains("''"));
    });

    test('escapes special characters in query', () {
      final script = service.generateFindScript("it's");
      expect(script, contains(r"it\'s"));
    });

    test('includes TreeWalker for DOM traversal', () {
      final script = service.generateFindScript('search');
      expect(script, contains('createTreeWalker'));
    });

    test('creates mark elements with correct class', () {
      final script = service.generateFindScript('word');
      expect(script, contains('-find-highlight'));
      expect(script, contains("createElement('mark')"));
    });

    test('highlights first match as active', () {
      final script = service.generateFindScript('word');
      expect(script, contains('-find-active'));
      expect(script, contains('#FF9800')); // active color
    });

    test('scrolls first match into view', () {
      final script = service.generateFindScript('word');
      expect(script, contains('scrollIntoView'));
    });

    test('skips SCRIPT, STYLE, and NOSCRIPT tags', () {
      final script = service.generateFindScript('code');
      expect(script, contains("'SCRIPT'"));
      expect(script, contains("'STYLE'"));
      expect(script, contains("'NOSCRIPT'"));
    });

    test('returns totalMatches as string', () {
      final script = service.generateFindScript('test');
      expect(script, contains('return totalMatches.toString()'));
    });

    test('is a self-executing function', () {
      final script = service.generateFindScript('test');
      expect(script.trim(), startsWith('(function()'));
      expect(script.trim(), endsWith('})()'));
    });
  });

  group('generateNavigateScript', () {
    test('returns fallback for zero matches', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 0,
        forward: true,
      );
      expect(script, contains("'0'"));
    });

    test('wraps forward to first match', () {
      final script = service.generateNavigateScript(
        currentIndex: 4,
        totalMatches: 5,
        forward: true,
      );
      // (4 + 1) % 5 = 0
      expect(script, contains('var target = 0'));
    });

    test('increments index when going forward', () {
      final script = service.generateNavigateScript(
        currentIndex: 1,
        totalMatches: 5,
        forward: true,
      );
      // (1 + 1) % 5 = 2
      expect(script, contains('var target = 2'));
    });

    test('wraps backward to last match', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 5,
        forward: false,
      );
      // (0 - 1 + 5) % 5 = 4
      expect(script, contains('var target = 4'));
    });

    test('decrements index when going backward', () {
      final script = service.generateNavigateScript(
        currentIndex: 3,
        totalMatches: 5,
        forward: false,
      );
      // (3 - 1 + 5) % 5 = 2
      expect(script, contains('var target = 2'));
    });

    test('removes active class from all marks', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 3,
        forward: true,
      );
      expect(script, contains('find-active'));
      expect(script, contains('remove'));
    });

    test('adds active class to target mark', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 3,
        forward: true,
      );
      expect(script, contains('find-active'));
      expect(script, contains('add'));
    });

    test('scrolls target into view', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 2,
        forward: true,
      );
      expect(script, contains('scrollIntoView'));
    });

    test('handles single match forward', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 1,
        forward: true,
      );
      // (0 + 1) % 1 = 0
      expect(script, contains('var target = 0'));
    });

    test('handles single match backward', () {
      final script = service.generateNavigateScript(
        currentIndex: 0,
        totalMatches: 1,
        forward: false,
      );
      // (0 - 1 + 1) % 1 = 0
      expect(script, contains('var target = 0'));
    });
  });

  group('generateClearScript', () {
    test('selects all highlighted marks', () {
      final script = service.generateClearScript();
      expect(script, contains('mark.'));
      expect(script, contains('find-highlight'));
    });

    test('replaces marks with text nodes', () {
      final script = service.generateClearScript();
      expect(script, contains('replaceChild'));
      expect(script, contains('createTextNode'));
    });

    test('normalizes parent nodes', () {
      final script = service.generateClearScript();
      expect(script, contains('normalize'));
    });

    test('returns zero string', () {
      final script = service.generateClearScript();
      expect(script, contains("return '0'"));
    });

    test('is a self-executing function', () {
      final script = service.generateClearScript();
      expect(script.trim(), startsWith('(function()'));
      expect(script.trim(), endsWith('})()'));
    });
  });
}
