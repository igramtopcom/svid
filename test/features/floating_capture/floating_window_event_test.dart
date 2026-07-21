import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/domain/entities/floating_window_event.dart';
import 'package:svid/features/floating_capture/domain/entities/snooze_duration.dart';

void main() {
  test('exhaustive switch compiles for every event variant', () {
    // This test fails at *compile* time if a new sealed subclass is added
    // without updating the switch — the analyzer flags missing cases on
    // sealed types. At runtime we just confirm the function runs through
    // each variant without throwing.
    String describe(FloatingWindowEvent e) {
      switch (e) {
        case DownloadClicked(:final url):
          return 'download:$url';
        case SnoozeSelected(:final duration):
          return 'snooze:${duration.wireKey}';
        case MenuOpenAppRequested():
          return 'menu:openApp';
        case MenuOpenSettingsRequested():
          return 'menu:openSettings';
        case PositionChanged(:final x, :final y, :final monitorId):
          return 'pos:$monitorId@$x,$y';
        case PopupDismissed():
          return 'dismissed';
        case ThumbnailClicked(:final url):
          return 'thumb:$url';
        case OpenInAppClicked(:final url):
          return 'openInApp:$url';
        case OpenSavedFolderClicked(:final path):
          return 'openFolder:$path';
        case PlayFileClicked(:final path):
          return 'play:$path';
      }
    }

    expect(describe(const DownloadClicked(url: 'u1')), 'download:u1');
    expect(
      describe(const SnoozeSelected(SnoozeDuration.oneHour)),
      'snooze:oneHour',
    );
    expect(describe(const MenuOpenAppRequested()), 'menu:openApp');
    expect(describe(const MenuOpenSettingsRequested()), 'menu:openSettings');
    expect(
      describe(
        const PositionChanged(x: 100, y: 200, monitorId: 'monitor-0'),
      ),
      'pos:monitor-0@100.0,200.0',
    );
    expect(describe(const PopupDismissed()), 'dismissed');
    expect(describe(const ThumbnailClicked('u2')), 'thumb:u2');
    expect(describe(const OpenInAppClicked('u3')), 'openInApp:u3');
  });

  test('DownloadClicked carries optional preset key', () {
    const e = DownloadClicked(url: 'u', presetKey: '1080p-mp4');
    expect(e.presetKey, '1080p-mp4');
    expect(const DownloadClicked(url: 'u').presetKey, isNull);
  });
}
