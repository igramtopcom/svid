import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/data/datasources/desktop_multi_window_floating_window.dart';
import 'package:svid/features/floating_capture/domain/entities/floating_window_event.dart';
import 'package:svid/features/floating_capture/domain/entities/snooze_duration.dart';

/// v2.2 Phase 2C reviewer-3 Fix 6: tests for bridge predicates that the
/// reviewer correctly noted were missing. parseFloatingWindowEvent is
/// already covered; these target [isTerminalHideEvent] +
/// [isPopupAutoHiddenMethod] which decide whether main-side defensively
/// hides the OS window on each incoming popup event.
void main() {
  group('isTerminalHideEvent — closes popup window on main side', () {
    test('PopupDismissed → terminal hide', () {
      expect(isTerminalHideEvent(const PopupDismissed()), isTrue);
    });

    test('OpenInAppClicked → terminal hide', () {
      expect(
        isTerminalHideEvent(
          const OpenInAppClicked('https://www.youtube.com/watch?v=abc'),
        ),
        isTrue,
      );
    });

    test('MenuOpenAppRequested → terminal hide', () {
      expect(isTerminalHideEvent(const MenuOpenAppRequested()), isTrue);
    });

    test('MenuOpenSettingsRequested → terminal hide', () {
      expect(isTerminalHideEvent(const MenuOpenSettingsRequested()), isTrue);
    });

    test('SnoozeSelected → terminal hide', () {
      expect(
        isTerminalHideEvent(const SnoozeSelected(SnoozeDuration.thirtyMinutes)),
        isTrue,
      );
    });

    test('DownloadClicked(directDownload: false) → terminal hide '
        '(secondary "Tuỳ chọn…" opens dialog → popup goes away)', () {
      expect(
        isTerminalHideEvent(
          const DownloadClicked(
            url: 'https://www.youtube.com/watch?v=abc',
            directDownload: false,
          ),
        ),
        isTrue,
      );
    });

    test('DownloadClicked(directDownload: true) → NOT terminal hide '
        '(reviewer-2 P0a fix: popup must stay visible for State 6 banner)', () {
      expect(
        isTerminalHideEvent(
          const DownloadClicked(
            url: 'https://www.youtube.com/watch?v=abc',
            directDownload: true,
          ),
        ),
        isFalse,
      );
    });

    test('DownloadClicked default (no flag) → NOT terminal hide '
        '(forward-compat: older popups without flag map to direct download '
        'per CaptureDownloadRequest default)', () {
      expect(
        isTerminalHideEvent(
          const DownloadClicked(url: 'https://www.youtube.com/watch?v=abc'),
        ),
        isFalse,
      );
    });

    test('ThumbnailClicked → NOT terminal hide '
        '(thumbnail click opens external browser; popup must stay visible '
        'so user can still click Download)', () {
      expect(
        isTerminalHideEvent(
          const ThumbnailClicked('https://www.youtube.com/watch?v=abc'),
        ),
        isFalse,
      );
    });

    test('PositionChanged → NOT terminal hide '
        '(drag persistence event; popup is mid-interaction)', () {
      expect(
        isTerminalHideEvent(
          const PositionChanged(x: 100, y: 200, monitorId: 'mon-0'),
        ),
        isFalse,
      );
    });

    test('OpenSavedFolderClicked → terminal hide '
        '(Phase 2D.1: clicking "Mở thư mục" reveals in Finder/Explorer; '
        'popup is finished, retreat to idle)', () {
      expect(
        isTerminalHideEvent(
          const OpenSavedFolderClicked('/Users/x/Downloads/clip.mp4'),
        ),
        isTrue,
      );
    });

    test(
      'PlayFileClicked → terminal hide '
      '(Phase 2D.1: clicking "Phát" opens in-app player; popup finished)',
      () {
        expect(
          isTerminalHideEvent(
            const PlayFileClicked('/Users/x/Downloads/clip.mp4'),
          ),
          isTrue,
        );
      },
    );
  });

  group(
    'isPopupAutoHiddenMethod — visibility sync only, NOT a user action',
    () {
      test('exact "onPopupAutoHidden" → true', () {
        expect(isPopupAutoHiddenMethod('onPopupAutoHidden'), isTrue);
      });

      test('case mismatch → false (avoid false positives on typos)', () {
        expect(isPopupAutoHiddenMethod('onpopupautohidden'), isFalse);
        expect(isPopupAutoHiddenMethod('OnPopupAutoHidden'), isFalse);
      });

      test('PopupDismissed-shaped string → false', () {
        expect(isPopupAutoHiddenMethod('onPopupDismissed'), isFalse);
      });

      test('empty / arbitrary → false', () {
        expect(isPopupAutoHiddenMethod(''), isFalse);
        expect(isPopupAutoHiddenMethod('foo'), isFalse);
      });
    },
  );
}
