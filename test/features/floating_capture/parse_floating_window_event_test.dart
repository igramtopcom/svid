import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/data/datasources/desktop_multi_window_floating_window.dart';
import 'package:svid/features/floating_capture/domain/entities/floating_window_event.dart';
import 'package:svid/features/floating_capture/domain/entities/snooze_duration.dart';

void main() {
  group('onDownloadClicked', () {
    test('parses url + optional preset', () {
      final e = parseFloatingWindowEvent('onDownloadClicked', {
        'url': 'https://x',
        'presetKey': '1080p-mp4',
      }) as DownloadClicked;
      expect(e.url, 'https://x');
      expect(e.presetKey, '1080p-mp4');
    });

    test('preset omitted → null', () {
      final e = parseFloatingWindowEvent('onDownloadClicked', {
        'url': 'https://x',
      }) as DownloadClicked;
      expect(e.presetKey, isNull);
    });

    test('missing url → null event (drop)', () {
      expect(
        parseFloatingWindowEvent('onDownloadClicked', {'presetKey': 'x'}),
        isNull,
      );
    });

    test('non-map args → null', () {
      expect(parseFloatingWindowEvent('onDownloadClicked', null), isNull);
      expect(parseFloatingWindowEvent('onDownloadClicked', 'string'), isNull);
    });

    test('v2.2: directDownload=true (Tải ngay) parsed', () {
      final e = parseFloatingWindowEvent('onDownloadClicked', {
        'url': 'https://x',
        'directDownload': true,
      }) as DownloadClicked;
      expect(e.directDownload, isTrue);
    });

    test('v2.2: directDownload=false (Tuỳ chọn…) parsed', () {
      final e = parseFloatingWindowEvent('onDownloadClicked', {
        'url': 'https://x',
        'directDownload': false,
      }) as DownloadClicked;
      expect(e.directDownload, isFalse);
    });

    test('v2.2: directDownload omitted → defaults true (forward-compat)', () {
      final e = parseFloatingWindowEvent('onDownloadClicked', {
        'url': 'https://x',
      }) as DownloadClicked;
      expect(e.directDownload, isTrue,
          reason: 'older popup engines without the flag map to "Tải ngay"');
    });
  });

  group('onSnoozeSelected', () {
    test('valid wireKey parses', () {
      final e = parseFloatingWindowEvent('onSnoozeSelected', {
        'duration': 'oneHour',
      }) as SnoozeSelected;
      expect(e.duration, SnoozeDuration.oneHour);
    });

    test('unknown wireKey → null (forward compat)', () {
      expect(
        parseFloatingWindowEvent('onSnoozeSelected', {
          'duration': 'oneCentury',
        }),
        isNull,
      );
    });

    test('missing duration → null', () {
      expect(parseFloatingWindowEvent('onSnoozeSelected', {}), isNull);
    });
  });

  group('menu events', () {
    test('onMenuOpenApp returns const event', () {
      expect(
        parseFloatingWindowEvent('onMenuOpenApp', null),
        isA<MenuOpenAppRequested>(),
      );
    });

    test('onMenuOpenSettings returns const event', () {
      expect(
        parseFloatingWindowEvent('onMenuOpenSettings', null),
        isA<MenuOpenSettingsRequested>(),
      );
    });
  });

  group('onPositionChanged', () {
    test('coerces num to double for x + y', () {
      final e = parseFloatingWindowEvent('onPositionChanged', {
        'x': 100, // int
        'y': 200.5, // double
        'monitorId': 'mon-0',
      }) as PositionChanged;
      expect(e.x, 100.0);
      expect(e.y, 200.5);
      expect(e.monitorId, 'mon-0');
    });

    test('any missing field → null', () {
      expect(
        parseFloatingWindowEvent('onPositionChanged', {
          'y': 0,
          'monitorId': 'm',
        }),
        isNull,
        reason: 'missing x',
      );
      expect(
        parseFloatingWindowEvent('onPositionChanged', {
          'x': 0,
          'monitorId': 'm',
        }),
        isNull,
        reason: 'missing y',
      );
      expect(
        parseFloatingWindowEvent('onPositionChanged', {'x': 0, 'y': 0}),
        isNull,
        reason: 'missing monitorId',
      );
    });
  });

  group('onPopupDismissed', () {
    test('no args needed', () {
      expect(
        parseFloatingWindowEvent('onPopupDismissed', null),
        isA<PopupDismissed>(),
      );
    });
  });

  group('onThumbnailClicked / onOpenInAppClicked', () {
    test('thumbnail url required', () {
      final e = parseFloatingWindowEvent('onThumbnailClicked', {
        'url': 'https://yt/img.jpg',
      }) as ThumbnailClicked;
      expect(e.url, 'https://yt/img.jpg');

      expect(parseFloatingWindowEvent('onThumbnailClicked', {}), isNull);
    });

    test('open-in-app url required', () {
      final e = parseFloatingWindowEvent('onOpenInAppClicked', {
        'url': 'https://playlist',
      }) as OpenInAppClicked;
      expect(e.url, 'https://playlist');

      expect(parseFloatingWindowEvent('onOpenInAppClicked', {}), isNull);
    });
  });

  group('onOpenSavedFolder / onPlayFile (Phase 2D.1)', () {
    test('onOpenSavedFolder parses path', () {
      final e = parseFloatingWindowEvent('onOpenSavedFolder', {
        'path': '/Users/x/Downloads/clip.mp4',
      }) as OpenSavedFolderClicked;
      expect(e.path, '/Users/x/Downloads/clip.mp4');
    });

    test('onOpenSavedFolder missing path → null', () {
      expect(parseFloatingWindowEvent('onOpenSavedFolder', {}), isNull);
    });

    test('onOpenSavedFolder empty path → null (defensive drop)', () {
      expect(
        parseFloatingWindowEvent('onOpenSavedFolder', {'path': ''}),
        isNull,
        reason: 'empty path would crash Process.run("open", ["-R", ""])',
      );
    });

    test('onPlayFile parses path', () {
      final e = parseFloatingWindowEvent('onPlayFile', {
        'path': '/Users/x/Downloads/clip.mp4',
      }) as PlayFileClicked;
      expect(e.path, '/Users/x/Downloads/clip.mp4');
    });

    test('onPlayFile missing path → null', () {
      expect(parseFloatingWindowEvent('onPlayFile', {}), isNull);
    });

    test('onPlayFile empty path → null (defensive drop)', () {
      expect(
        parseFloatingWindowEvent('onPlayFile', {'path': ''}),
        isNull,
      );
    });

    test('non-map args → null for both', () {
      expect(parseFloatingWindowEvent('onOpenSavedFolder', null), isNull);
      expect(parseFloatingWindowEvent('onPlayFile', 'string'), isNull);
    });
  });

  group('forward compat', () {
    test('unknown method name returns null (silent drop)', () {
      expect(
        parseFloatingWindowEvent('onSomeFutureV3Event', {'foo': 'bar'}),
        isNull,
      );
    });
  });
}
