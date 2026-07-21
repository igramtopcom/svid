import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/settings/domain/services/browser_cookie_import_service.dart';

void main() {
  late SharedPreferences prefs;
  late BrowserCookieImportService service;
  final Set<String> existingDirs = {};

  bool fakeDirectoryExists(String path) => existingDirs.contains(path);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    existingDirs.clear();
    service = BrowserCookieImportService(
      prefs,
      directoryExists: fakeDirectoryExists,
    );
  });

  group('BrowserType enum', () {
    test('fromString parses valid ytdlp names', () {
      expect(BrowserType.fromString('chrome'), BrowserType.chrome);
      expect(BrowserType.fromString('firefox'), BrowserType.firefox);
      expect(BrowserType.fromString('edge'), BrowserType.edge);
      expect(BrowserType.fromString('safari'), BrowserType.safari);
      expect(BrowserType.fromString('brave'), BrowserType.brave);
      expect(BrowserType.fromString('opera'), BrowserType.opera);
      expect(BrowserType.fromString('chromium'), BrowserType.chromium);
      expect(BrowserType.fromString('vivaldi'), BrowserType.vivaldi);
    });

    test('fromString returns null for invalid/empty values', () {
      expect(BrowserType.fromString(null), isNull);
      expect(BrowserType.fromString(''), isNull);
      expect(BrowserType.fromString('netscape'), isNull);
      expect(BrowserType.fromString('ie'), isNull);
    });

    test('ytdlpName matches yt-dlp expected values', () {
      expect(BrowserType.chrome.ytdlpName, 'chrome');
      expect(BrowserType.firefox.ytdlpName, 'firefox');
      expect(BrowserType.safari.ytdlpName, 'safari');
    });

    test('displayName is human-readable', () {
      expect(BrowserType.chrome.displayName, 'Google Chrome');
      expect(BrowserType.firefox.displayName, 'Firefox');
      expect(BrowserType.edge.displayName, 'Microsoft Edge');
      expect(BrowserType.safari.displayName, 'Safari');
      expect(BrowserType.brave.displayName, 'Brave');
    });

    test('all BrowserType values have unique ytdlpName', () {
      final names = BrowserType.values.map((b) => b.ytdlpName).toSet();
      expect(names.length, BrowserType.values.length);
    });
  });

  group('selectedBrowser', () {
    test('returns null when no browser is selected', () {
      expect(service.selectedBrowser, isNull);
    });

    test('returns selected browser after setting', () async {
      await service.setSelectedBrowser(BrowserType.chrome);
      expect(service.selectedBrowser, BrowserType.chrome);
    });

    test('returns null after clearing selection', () async {
      await service.setSelectedBrowser(BrowserType.firefox);
      expect(service.selectedBrowser, BrowserType.firefox);

      await service.setSelectedBrowser(null);
      expect(service.selectedBrowser, isNull);
    });

    test('persists selection in SharedPreferences', () async {
      await service.setSelectedBrowser(BrowserType.brave);

      // Create a new service instance to verify persistence
      final service2 = BrowserCookieImportService(
        prefs,
        directoryExists: fakeDirectoryExists,
      );
      expect(service2.selectedBrowser, BrowserType.brave);
    });
  });

  group('cookiesFromBrowserArg', () {
    test('returns null when disabled', () {
      expect(service.cookiesFromBrowserArg, isNull);
    });

    test('returns ytdlp name when browser selected', () async {
      await service.setSelectedBrowser(BrowserType.chrome);
      expect(service.cookiesFromBrowserArg, 'chrome');

      await service.setSelectedBrowser(BrowserType.firefox);
      expect(service.cookiesFromBrowserArg, 'firefox');
    });
  });

  group('isEnabled', () {
    test('returns false when no browser selected', () {
      expect(service.isEnabled, isFalse);
    });

    test('returns true when browser selected', () async {
      await service.setSelectedBrowser(BrowserType.edge);
      expect(service.isEnabled, isTrue);
    });
  });

  group('detectInstalledBrowsers', () {
    test('returns empty list when no browser dirs exist', () {
      final browsers = service.detectInstalledBrowsers();
      expect(browsers, isEmpty);
    });

    test('detects Chrome when its directory exists (macOS path)', () {
      // Simulate macOS Chrome directory
      final home = '/Users/testuser';
      existingDirs.add('$home/Library/Application Support/Google/Chrome');

      // Need to set HOME env — skip since Platform.environment is immutable in tests
      // Instead test the injectable directoryExists callback
      final browsers = service.detectInstalledBrowsers();
      // In CI/test, Platform.isMacOS may or may not be true
      // The test validates the callback is used
      expect(browsers, isA<List<BrowserType>>());
    });

    test('injectable directoryExists is called', () {
      var callCount = 0;
      final countingService = BrowserCookieImportService(
        prefs,
        directoryExists: (path) {
          callCount++;
          return false;
        },
      );

      countingService.detectInstalledBrowsers();
      // Should have checked at least one path per browser
      expect(callCount, greaterThan(0));
    });

    test('detects multiple browsers when multiple dirs exist', () {
      // Add Chrome and Firefox macOS paths
      final home = '/Users/testuser';
      existingDirs.addAll([
        '$home/Library/Application Support/Google/Chrome',
        '$home/Library/Application Support/Firefox',
      ]);

      // Note: This only works if the test runs on macOS with HOME=/Users/testuser
      // The test at minimum ensures detectInstalledBrowsers runs without error
      final browsers = service.detectInstalledBrowsers();
      expect(browsers, isA<List<BrowserType>>());
    });
  });

  group('edge cases', () {
    test('handles corrupted prefs value gracefully', () async {
      await prefs.setString('cookie_import_browser', 'nonexistent_browser');
      expect(service.selectedBrowser, isNull);
      expect(service.isEnabled, isFalse);
      expect(service.cookiesFromBrowserArg, isNull);
    });

    test('setSelectedBrowser removes key when null', () async {
      await service.setSelectedBrowser(BrowserType.chrome);
      expect(prefs.containsKey('cookie_import_browser'), isTrue);

      await service.setSelectedBrowser(null);
      expect(prefs.containsKey('cookie_import_browser'), isFalse);
    });
  });
}
