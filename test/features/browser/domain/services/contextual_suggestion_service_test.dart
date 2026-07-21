import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/contextual_suggestion_service.dart';

void main() {
  group('ContextualSuggestionService.analyze', () {
    // ── Edge cases ────────────────────────────────────────────────────────────
    test('returns null for empty string', () {
      expect(ContextualSuggestionService.analyze(''), isNull);
    });

    test('returns null for invalid URL', () {
      expect(ContextualSuggestionService.analyze('not a url'), isNull);
    });

    test('returns null for URL without authority', () {
      expect(ContextualSuggestionService.analyze('file:///local/path'), isNull);
    });

    test('returns null for YouTube homepage', () {
      expect(ContextualSuggestionService.analyze('https://www.youtube.com/'), isNull);
    });

    test('returns null for YouTube watch page without list param', () {
      expect(
        ContextualSuggestionService.analyze(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });

    test('returns null for YouTube search results', () {
      expect(
        ContextualSuggestionService.analyze(
            'https://www.youtube.com/results?search_query=cats'),
        isNull,
      );
    });

    // ── YouTube playlist ──────────────────────────────────────────────────────
    test('detects YouTube playlist page', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknc9TTngeaYzA');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubePlaylist);
    });

    test('does NOT detect watch page with list param', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/watch?v=abc&list=PLxyz');
      expect(result, isNull);
    });

    test('detectedUrl matches input URL for playlist', () {
      const url = 'https://www.youtube.com/playlist?list=PLtest';
      final result = ContextualSuggestionService.analyze(url);
      expect(result!.detectedUrl, url);
    });

    // ── YouTube channel ───────────────────────────────────────────────────────
    test('detects YouTube @handle channel', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/@MrBeast');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubeChannel);
    });

    test('detects YouTube @handle/videos tab', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/@PewDiePie/videos');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubeChannel);
    });

    test('detects YouTube /channel/<id>', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubeChannel);
    });

    test('detects YouTube /c/<customUrl>', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/c/GoogleDevelopers');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubeChannel);
    });

    test('detects YouTube /user/<username>', () {
      final result = ContextualSuggestionService.analyze(
          'https://www.youtube.com/user/LinusTechTips');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.youtubeChannel);
    });

    // ── Vimeo showcase ────────────────────────────────────────────────────────
    test('detects Vimeo showcase', () {
      final result = ContextualSuggestionService.analyze(
          'https://vimeo.com/showcase/12345678');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.vimeoShowcase);
    });

    test('detects Vimeo album', () {
      final result = ContextualSuggestionService.analyze(
          'https://vimeo.com/album/87654321');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.vimeoShowcase);
    });

    test('returns null for Vimeo individual video', () {
      expect(
        ContextualSuggestionService.analyze('https://vimeo.com/123456789'),
        isNull,
      );
    });

    // ── Generic series ────────────────────────────────────────────────────────
    test('detects /series/ path', () {
      final result = ContextualSuggestionService.analyze(
          'https://example.com/series/breaking-bad');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.genericSeries);
    });

    test('detects /season-N path', () {
      final result = ContextualSuggestionService.analyze(
          'https://example.com/show/game-of-thrones/season-3');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.genericSeries);
    });

    test('detects /episode-N path', () {
      final result = ContextualSuggestionService.analyze(
          'https://example.com/show/episode-5');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.genericSeries);
    });

    test('detects SxxExx style path', () {
      final result = ContextualSuggestionService.analyze(
          'https://example.com/show/s01e03-pilot');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.genericSeries);
    });

    test('detects /playlist/ path on non-YouTube host', () {
      final result = ContextualSuggestionService.analyze(
          'https://soundcloud.com/artist/playlist/summer-mix');
      expect(result, isNotNull);
      expect(result!.type, SuggestionType.genericSeries);
    });

    // ── DownloadSuggestion equality ───────────────────────────────────────────
    test('equal suggestions are equal', () {
      const url = 'https://www.youtube.com/playlist?list=PLtest';
      final a = ContextualSuggestionService.analyze(url);
      final b = ContextualSuggestionService.analyze(url);
      expect(a, equals(b));
    });

    test('suggestions with different URLs are not equal', () {
      final a = ContextualSuggestionService.analyze(
          'https://www.youtube.com/playlist?list=PLaaa');
      final b = ContextualSuggestionService.analyze(
          'https://www.youtube.com/playlist?list=PLbbb');
      expect(a, isNot(equals(b)));
    });
  });
}
