import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/tray_service.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = TrayService();

  setUp(() {
    service.onNewDownload = null;
    service.onShowDownloads = null;
    service.onSettings = null;
    TrayService.showWindowOverride = null;
    TrayService.closeWindowOverride = null;
  });

  group('trayTooltipForDownloads', () {
    test('returns app name only when there are no active downloads', () {
      expect(trayTooltipForDownloads(0), 'SSvid');
    });

    test('uses singular wording for one active download', () {
      expect(trayTooltipForDownloads(1), 'SSvid — 1 active download');
    });

    test('uses plural wording for multiple active downloads', () {
      expect(trayTooltipForDownloads(3), 'SSvid — 3 active downloads');
    });
  });

  group('TrayService menu routing', () {
    test('show menu item shows the window', () async {
      var showCalls = 0;
      TrayService.showWindowOverride = () async => showCalls++;

      service.onTrayMenuItemClick(MenuItem(key: 'show', label: 'Show'));
      await Future<void>.delayed(Duration.zero);

      expect(showCalls, 1);
    });

    test('new_download shows window and invokes callback', () async {
      var showCalls = 0;
      var callbackCalls = 0;
      TrayService.showWindowOverride = () async => showCalls++;
      service.onNewDownload = () => callbackCalls++;

      service.onTrayMenuItemClick(
        MenuItem(key: 'new_download', label: 'New Download'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(showCalls, 1);
      expect(callbackCalls, 1);
    });

    test('downloads shows window and invokes callback', () async {
      var showCalls = 0;
      var callbackCalls = 0;
      TrayService.showWindowOverride = () async => showCalls++;
      service.onShowDownloads = () => callbackCalls++;

      service.onTrayMenuItemClick(
        MenuItem(key: 'downloads', label: 'Show Downloads'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(showCalls, 1);
      expect(callbackCalls, 1);
    });

    test('settings shows window and invokes callback', () async {
      var showCalls = 0;
      var callbackCalls = 0;
      TrayService.showWindowOverride = () async => showCalls++;
      service.onSettings = () => callbackCalls++;

      service.onTrayMenuItemClick(MenuItem(key: 'settings', label: 'Settings'));
      await Future<void>.delayed(Duration.zero);

      expect(showCalls, 1);
      expect(callbackCalls, 1);
    });

    test('quit invokes close window action', () async {
      var closeCalls = 0;
      TrayService.closeWindowOverride = () async => closeCalls++;

      service.onTrayMenuItemClick(MenuItem(key: 'quit', label: 'Quit'));
      await Future<void>.delayed(Duration.zero);

      expect(closeCalls, 1);
    });
  });
}
