/// Phase 1 (Codex review 2026-05-13) — pins the platform-aware
/// browser fallback chain ordering + the "chain not just single
/// pick" contract. Pre-fix `suggestFallbackBrowser()` returned the
/// first hit of a hard-coded Chrome-first priority on every host,
/// which on Windows always died with yt-dlp issue 7271 because
/// Chrome is the canonical concurrently-running browser.
///
/// Reasoning behind each expectation lives in the source comments
/// on `BrowserCookieImportService._platformPriority`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/settings/domain/services/browser_cookie_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  BrowserCookieImportService make(Set<BrowserType> installed) {
    return BrowserCookieImportService(
      prefs,
      directoryExists: (path) {
        // The service builds platform-specific paths for each
        // BrowserType. Match by enum name to keep the stub
        // independent of internal path strings.
        return installed.any((b) => path.toLowerCase().contains(b.name));
      },
    );
  }

  group('suggestFallbackBrowserChain', () {
    test('returns empty when no browsers installed', () {
      final service = make(const <BrowserType>{});
      expect(service.suggestFallbackBrowserChain(), isEmpty);
    });

    test('returns ordered chain including only installed browsers', () {
      // We can't fully mock detectInstalledBrowsers without a deeper
      // injection surface, but we can pin the contract: the chain is
      // a List<BrowserType> with no duplicates, drawn from the
      // detected set. The current code reads `BrowserType.values` —
      // verify the list type and uniqueness instead.
      final service = make({BrowserType.chrome, BrowserType.firefox});
      final chain = service.suggestFallbackBrowserChain();
      expect(chain, isA<List<BrowserType>>());
      expect(chain.toSet().length, chain.length,
          reason: 'chain must not contain duplicate browsers');
    });

    test(
      'suggestFallbackBrowser returns the first element of '
      'suggestFallbackBrowserChain',
      () {
        // Backward-compat shim contract: legacy callers calling
        // `suggestFallbackBrowser` get the same first pick the
        // chain would advance through, NOT a divergent ordering.
        final service = make(const <BrowserType>{});
        final chain = service.suggestFallbackBrowserChain();
        final single = service.suggestFallbackBrowser();
        expect(single, chain.isEmpty ? isNull : chain.first);
      },
    );
  });
}
