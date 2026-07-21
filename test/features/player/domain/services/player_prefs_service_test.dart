// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/player/domain/services/player_prefs_service.dart';

void main() {
  late PlayerPrefsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = PlayerPrefsService(prefs);
  });

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  group('CRUD', () {
    const url = 'https://www.youtube.com/watch?v=abc123';

    test('getPrefs returns null when nothing saved', () async {
      expect(await service.getPrefs(url), isNull);
    });

    test('savePrefs + getPrefs round-trips all fields', () async {
      const p = PlayerPrefs(
        speed: 1.5,
        volume: 0.8,
        subtitleTrackId: 'sub1',
        audioTrackId: 'audio2',
        subtitleFontSize: 24.0,
        subtitleDelay: 300,
      );
      await service.savePrefs(url, p);
      final loaded = await service.getPrefs(url);

      expect(loaded, isNotNull);
      expect(loaded!.speed, 1.5);
      expect(loaded.volume, 0.8);
      expect(loaded.subtitleTrackId, 'sub1');
      expect(loaded.audioTrackId, 'audio2');
      expect(loaded.subtitleFontSize, 24.0);
      expect(loaded.subtitleDelay, 300);
    });

    test('clearPrefs removes saved prefs', () async {
      await service.savePrefs(url, const PlayerPrefs(speed: 2.0));
      await service.clearPrefs(url);
      expect(await service.getPrefs(url), isNull);
    });

    test('clearAll removes all player pref keys', () async {
      const url2 = 'https://example.com/video/1';
      await service.savePrefs(url, const PlayerPrefs(speed: 1.5));
      await service.savePrefs(url2, const PlayerPrefs(volume: 0.5));
      await service.clearAll();
      expect(await service.getPrefs(url), isNull);
      expect(await service.getPrefs(url2), isNull);
    });

    test('getPrefs returns null and clears corrupt data', () async {
      final key = PlayerPrefsService.keyFor(url);
      SharedPreferences.setMockInitialValues({key: 'not-json'});
      final prefs = await SharedPreferences.getInstance();
      final svc = PlayerPrefsService(prefs);

      expect(await svc.getPrefs(url), isNull);
      // Key should be removed
      expect(prefs.getString(key), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // URL canonicalization
  // ---------------------------------------------------------------------------

  group('canonicalUrl', () {
    test('strips utm_source', () {
      const raw = 'https://www.youtube.com/watch?v=abc&utm_source=share';
      expect(
        PlayerPrefsService.canonicalUrl(raw),
        'https://www.youtube.com/watch?v=abc',
      );
    });

    test('strips si= (YouTube tracking)', () {
      const raw = 'https://youtu.be/abc123?si=xyz789';
      expect(
        PlayerPrefsService.canonicalUrl(raw),
        'https://youtu.be/abc123',
      );
    });

    test('preserves v= (YouTube video ID)', () {
      const raw = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc';
      final result = PlayerPrefsService.canonicalUrl(raw);
      expect(result, contains('v=dQw4w9WgXcQ'));
      expect(result, isNot(contains('si=')));
    });

    test('returns non-URL strings unchanged', () {
      const path = '/Users/alice/videos/movie.mp4';
      expect(PlayerPrefsService.canonicalUrl(path), path);
    });

    test('strips multiple tracking params at once', () {
      const raw =
          'https://example.com/v?id=1&utm_source=x&utm_medium=y&fbclid=z';
      final result = PlayerPrefsService.canonicalUrl(raw);
      expect(result, contains('id=1'));
      expect(result, isNot(contains('utm_')));
      expect(result, isNot(contains('fbclid')));
    });
  });

  // ---------------------------------------------------------------------------
  // PlayerPrefs defaults
  // ---------------------------------------------------------------------------

  group('PlayerPrefs defaults', () {
    test('default constructor has sensible defaults', () {
      const p = PlayerPrefs();
      expect(p.speed, 1.0);
      expect(p.volume, 1.0);
      expect(p.subtitleTrackId, isNull);
      expect(p.audioTrackId, isNull);
      expect(p.subtitleFontSize, 32.0);
      expect(p.subtitleDelay, 0);
    });

    test('fromJson fills defaults for missing fields', () {
      final p = PlayerPrefs.fromJson({});
      expect(p.speed, 1.0);
      expect(p.volume, 1.0);
      expect(p.subtitleFontSize, 32.0);
      expect(p.subtitleDelay, 0);
    });

    test('two URLs with same canonical produce same key', () {
      const a = 'https://youtube.com/watch?v=abc&utm_source=share';
      const b = 'https://youtube.com/watch?v=abc';
      expect(PlayerPrefsService.keyFor(a), PlayerPrefsService.keyFor(b));
    });

    test('two different video IDs produce different keys', () {
      const a = 'https://youtube.com/watch?v=abc';
      const b = 'https://youtube.com/watch?v=xyz';
      expect(PlayerPrefsService.keyFor(a), isNot(PlayerPrefsService.keyFor(b)));
    });
  });
}
