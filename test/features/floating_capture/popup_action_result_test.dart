import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/domain/entities/popup_action_result.dart';

void main() {
  group('PopupActionResult — JSON round-trip', () {
    test('Started preserves filename', () {
      const r = PopupActionStarted(filename: 'video.mp4');
      final json = r.toJson();
      expect(json, {'type': 'started', 'filename': 'video.mp4'});
      expect(PopupActionResult.fromJson(json), r);
    });

    test('Started preserves container recode notice', () {
      const r = PopupActionStarted(
        filename: 'video.avi',
        containerRecodeNotice: 'AVI requires media processing.',
      );
      final json = r.toJson();
      expect(json, {
        'type': 'started',
        'filename': 'video.avi',
        'containerRecodeNotice': 'AVI requires media processing.',
      });
      expect(PopupActionResult.fromJson(json), r);
    });

    test('Completed preserves filename + savedPath', () {
      const r = PopupActionCompleted(
        filename: 'video.mp4',
        savedPath: '/Users/me/Downloads/video.mp4',
      );
      final json = r.toJson();
      expect(json['type'], 'completed');
      expect(PopupActionResult.fromJson(json), r);
    });

    test('Failed preserves message (no errorCode — backwards compat)', () {
      const r = PopupActionFailed('yt-dlp: format unavailable');
      final json = r.toJson();
      // RC8.5: errorCode is omitted from JSON when null — older
      // popup builds reading new main-engine messages don't break.
      expect(json, {'type': 'failed', 'message': 'yt-dlp: format unavailable'});
      expect(PopupActionResult.fromJson(json), r);
    });

    test('Failed preserves errorCode (RC8.5 per-class CTA)', () {
      // RC8.5: error code carried over wire so the floating popup
      // renders per-class CTA + hint instead of generic message.
      const r = PopupActionFailed(
        'Cookie database is locked',
        errorCode: 'cookieDbLocked',
      );
      final json = r.toJson();
      expect(json, {
        'type': 'failed',
        'message': 'Cookie database is locked',
        'errorCode': 'cookieDbLocked',
      });
      final decoded = PopupActionResult.fromJson(json);
      expect(decoded, r);
      expect((decoded as PopupActionFailed).errorCode, 'cookieDbLocked');
    });

    test('Failed equality includes errorCode', () {
      // Two Failed with same message but different error codes are
      // NOT equal — regression guard for the equality contract.
      const a = PopupActionFailed('msg', errorCode: 'cookieDbLocked');
      const b = PopupActionFailed('msg', errorCode: 'jsRuntimeUnavailable');
      const c = PopupActionFailed('msg');
      expect(a == b, isFalse);
      expect(a == c, isFalse);
      expect(a, PopupActionFailed('msg', errorCode: 'cookieDbLocked'));
    });

    test('AuthRequired round-trips', () {
      const r = PopupActionAuthRequired();
      final json = r.toJson();
      expect(json, {'type': 'authRequired'});
      expect(PopupActionResult.fromJson(json), r);
    });
  });

  group('PopupActionResult — fromJson defensive', () {
    test('missing type → null', () {
      expect(PopupActionResult.fromJson({}), isNull);
      expect(PopupActionResult.fromJson({'foo': 'bar'}), isNull);
    });

    test('unknown type → null (forward compat for newer wire variant)', () {
      expect(PopupActionResult.fromJson({'type': 'futureVariant'}), isNull);
    });

    test('Started missing filename → null', () {
      expect(PopupActionResult.fromJson({'type': 'started'}), isNull);
    });

    test('Completed missing savedPath → null', () {
      expect(
        PopupActionResult.fromJson({'type': 'completed', 'filename': 'x'}),
        isNull,
      );
    });

    test('Failed missing message → null', () {
      expect(PopupActionResult.fromJson({'type': 'failed'}), isNull);
    });

    test('Non-string type field → null', () {
      expect(PopupActionResult.fromJson({'type': 123}), isNull);
    });
  });

  group('PopupActionResult — equality', () {
    test('two Started with same filename are equal', () {
      expect(
        const PopupActionStarted(filename: 'a.mp4'),
        const PopupActionStarted(filename: 'a.mp4'),
      );
    });

    test('Started vs Completed are NOT equal', () {
      expect(
        const PopupActionStarted(filename: 'a.mp4') ==
            const PopupActionCompleted(filename: 'a.mp4', savedPath: '/x'),
        isFalse,
      );
    });

    test('AuthRequired singleton equality', () {
      expect(const PopupActionAuthRequired(), const PopupActionAuthRequired());
    });
  });
}
