import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/auth/presentation/widgets/platform_login_dialog.dart';

/// Lock the marker-guard contract per Chairman + Codex Decision Package
/// 2026-05-21. Auto-save extension from YouTube-only → all supported
/// platforms hinges on these markers — if the guard is too loose, we
/// save anonymous cookies (false positive); too tight, real logins
/// fail to persist (false negative). Each case below pins a specific
/// behavior so future cookie schema drift surfaces as a test failure.
void main() {
  group('AuthMarkerSpec — anyOf vs allOf semantics', () {
    test('anyOf requires at least one marker present', () {
      const spec = AuthMarkerSpec(anyOf: {'A', 'B', 'C'});
      expect(spec.matches({'A'}), isTrue);
      expect(spec.matches({'B'}), isTrue);
      expect(spec.matches({'X', 'C'}), isTrue);
      expect(spec.matches({'X', 'Y'}), isFalse);
      expect(spec.matches({}), isFalse);
    });

    test('allOf requires every marker present', () {
      const spec = AuthMarkerSpec(allOf: {'A', 'B'});
      expect(spec.matches({'A', 'B'}), isTrue);
      expect(spec.matches({'A', 'B', 'C'}), isTrue);
      expect(spec.matches({'A'}), isFalse);
      expect(spec.matches({'B'}), isFalse);
      expect(spec.matches({}), isFalse);
    });

    test('empty spec (no anyOf, no allOf) matches nothing', () {
      const spec = AuthMarkerSpec();
      expect(spec.matches({'anything'}), isFalse);
      expect(spec.matches({}), isFalse);
    });
  });

  group('PlatformLoginDialog.hasRequiredAuthMarker', () {
    group('YouTube — anyOf SID family', () {
      test('classic SID alone passes', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('youtube', {'SID'}),
          isTrue,
        );
      });

      test('any single secure variant passes', () {
        for (final marker in [
          'HSID',
          'SSID',
          'APISID',
          'SAPISID',
          '__Secure-1PSID',
          '__Secure-3PSID',
        ]) {
          expect(
            PlatformLoginDialog.hasRequiredAuthMarker('youtube', {marker}),
            isTrue,
            reason: '$marker should be sufficient',
          );
        }
      });

      test('non-auth cookies (PREF, VISITOR_INFO1_LIVE) FAIL', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'youtube',
            {'PREF', 'VISITOR_INFO1_LIVE', 'CONSENT'},
          ),
          isFalse,
          reason: 'Anonymous YouTube cookies must NOT trigger save',
        );
      });

      test('case sensitive: lowercased SID fails', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('youtube', {'sid'}),
          isFalse,
          reason: 'Cookie names are case-sensitive per RFC 6265',
        );
      });

      test('empty cookie set fails', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('youtube', {}),
          isFalse,
        );
      });
    });

    group('Facebook — allOf {c_user, xs}', () {
      test('both c_user and xs present passes', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'facebook',
            {'c_user', 'xs', 'datr'},
          ),
          isTrue,
        );
      });

      test('only c_user (missing xs) FAILS', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('facebook', {'c_user'}),
          isFalse,
          reason: 'FB needs the auth-pair; c_user alone is insufficient',
        );
      });

      test('only xs (missing c_user) FAILS', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('facebook', {'xs'}),
          isFalse,
        );
      });

      test('only datr (anonymous tracking) FAILS', () {
        // datr is set even for logged-out FB visitors; must NOT
        // trigger save.
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'facebook',
            {'datr', 'sb', 'wd'},
          ),
          isFalse,
        );
      });
    });

    group('Instagram — sessionid alone is enough', () {
      test('sessionid passes', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'instagram',
            {'sessionid', 'csrftoken'},
          ),
          isTrue,
        );
      });

      test('only csrftoken (no sessionid) FAILS', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'instagram',
            {'csrftoken'},
          ),
          isFalse,
        );
      });
    });

    group('X / Twitter — auth_token', () {
      test('auth_token via twitter key passes', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'twitter',
            {'auth_token', 'ct0'},
          ),
          isTrue,
        );
      });

      test('auth_token via x key passes (same spec)', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'x',
            {'auth_token', 'ct0'},
          ),
          isTrue,
        );
      });

      test('only ct0 (CSRF only) FAILS', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('x', {'ct0'}),
          isFalse,
          reason: 'ct0 is CSRF token; need auth_token to be authenticated',
        );
      });
    });

    group('TikTok / Reddit / Pinterest — RC8.1 parity', () {
      // RC8.1 of Ultra Plan v3 — these 3 platforms have been in
      // browser_cookie_auto_capture_service since earlier, but the
      // dialog-driven re-login was skipping them (unknown platform
      // → no auto-save). RC8.1 closes the asymmetry — marker cookie
      // names sourced from browser_cookie_auto_capture_service.dart.
      test('tiktok sessionid alone triggers save', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'tiktok',
            {'sessionid'},
          ),
          isTrue,
          reason: 'RC8.1: TikTok now in authMarkers map',
        );
      });

      test('tiktok without sessionid never saves (defensive)', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'tiktok',
            {'sid_tt', 'sid_guard'},
          ),
          isFalse,
          reason: 'sessionid is the primary auth marker; sid_tt alone '
              'is NOT sufficient (matches browser_cookie_auto_capture_service '
              'requiredMarkers)',
        );
      });

      test('reddit reddit_session triggers save', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'reddit',
            {'reddit_session'},
          ),
          isTrue,
          reason: 'RC8.1: Reddit parity with auto-capture service',
        );
      });

      test('reddit token_v2 alone NOT sufficient', () {
        // token_v2 is the newer Reddit oauth token; reddit_session
        // is still the canonical auth marker the rest of the
        // capture chain expects.
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'reddit',
            {'token_v2'},
          ),
          isFalse,
        );
      });

      test('pinterest _pinterest_sess triggers save', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'pinterest',
            {'_pinterest_sess'},
          ),
          isTrue,
          reason: 'RC8.1: Pinterest parity with auto-capture service',
        );
      });
    });

    group('Unknown platform — defensive opt-in only', () {
      test('arbitrary platform name fails', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'somenewsite',
            {'anyCookie'},
          ),
          isFalse,
        );
      });
    });

    group('Case-insensitive platform name', () {
      test('mixed-case "YouTube" matches "youtube" spec', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker('YouTube', {'SID'}),
          isTrue,
        );
      });

      test('uppercase "FACEBOOK" matches', () {
        expect(
          PlatformLoginDialog.hasRequiredAuthMarker(
            'FACEBOOK',
            {'c_user', 'xs'},
          ),
          isTrue,
        );
      });
    });
  });
}
