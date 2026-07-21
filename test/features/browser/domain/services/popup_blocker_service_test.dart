import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/popup_blocker_service.dart';

void main() {
  late PopupBlockerService service;

  setUp(() {
    service = PopupBlockerService();
  });

  group('PopupBlockerService.shouldBlockPopup', () {
    test('allows same-origin popup', () {
      expect(
        service.shouldBlockPopup(
          'https://www.youtube.com/watch?v=abc',
          'https://www.youtube.com/channel/xyz',
        ),
        isFalse,
      );
    });

    test('allows same root domain popup (subdomain)', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com/page',
          'https://login.example.com/auth',
        ),
        isFalse,
      );
    });

    test('blocks cross-origin popup', () {
      expect(
        service.shouldBlockPopup(
          'https://www.youtube.com/watch?v=abc',
          'https://www.adsite.com/popup',
        ),
        isTrue,
      );
    });

    test('blocks known popup domain popads.net', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          'https://c1.popads.net/pop.js',
        ),
        isTrue,
      );
    });

    test('blocks known popup domain exoclick.com', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          'https://main.exoclick.com/serve',
        ),
        isTrue,
      );
    });

    test('blocks javascript: scheme', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          'javascript:void(0)',
        ),
        isTrue,
      );
    });

    test('blocks data: scheme', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          'data:text/html,<h1>Popup</h1>',
        ),
        isTrue,
      );
    });

    test('blocks invalid popup URL', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          '',
        ),
        isTrue,
      );
    });

    test('blocks when current URL is invalid', () {
      expect(
        service.shouldBlockPopup(
          '',
          'https://www.example.com',
        ),
        isTrue,
      );
    });

    test('blocks adf.ly short links', () {
      expect(
        service.shouldBlockPopup(
          'https://www.example.com',
          'https://adf.ly/abc123',
        ),
        isTrue,
      );
    });
  });

  group('PopupBlockerService.generateBlockPopupsScript', () {
    test('returns non-empty JavaScript', () {
      final script = service.generateBlockPopupsScript();
      expect(script, isNotEmpty);
    });

    test('overrides window.open', () {
      final script = service.generateBlockPopupsScript();
      expect(script, contains('window.open'));
    });

    test('uses brand-prefixed popup_blocked flag', () {
      final script = service.generateBlockPopupsScript();
      expect(script, contains('_popup_blocked'));
    });

    test('is self-executing function', () {
      final script = service.generateBlockPopupsScript();
      expect(script.trim(), startsWith('(function()'));
    });
  });
}
