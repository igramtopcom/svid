import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/auth/domain/entities/platform_cookie.dart';
import 'package:ssvid/core/auth/domain/repositories/cookie_repository.dart';
import 'package:ssvid/core/config/brand_config.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/browser/domain/services/cookie_transfer_service.dart';

class _FakeCookieRepository implements CookieRepository {
  final savedCookies = <String, String>{};
  final savedExpiries = <String, DateTime?>{};

  @override
  Future<Result<void>> saveCookies({
    required String platform,
    required String cookieString,
    DateTime? expiresAt,
  }) async {
    savedCookies[platform] = cookieString;
    savedExpiries[platform] = expiresAt;
    return const Result.success(null);
  }

  @override
  Future<Result<PlatformCookie?>> getCookies(String platform) =>
      throw UnimplementedError();

  @override
  Future<Result<List<PlatformCookie>>> getAllCookies() =>
      throw UnimplementedError();

  @override
  Future<Result<bool>> hasCookies(String platform) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> removeCookies(String platform) =>
      throw UnimplementedError();

  @override
  Future<Result<int>> removeAllCookies() => throw UnimplementedError();

  @override
  Future<Result<String?>> getCookieString(String platform) =>
      throw UnimplementedError();
}

void main() {
  late CookieTransferService service;
  late _FakeCookieRepository fakeRepo;
  // Header is brand-stamped at runtime via BrandConfig.current.appName, so
  // tests must compose their fixtures the same way the production service
  // does — hard-coding "SSvid" fails the vidcombo build.
  final header = '# ${BrandConfig.current.appName} Cookie Export v1';

  setUp(() {
    fakeRepo = _FakeCookieRepository();
    service = CookieTransferService(fakeRepo);
  });

  group('exportAllCookies', () {
    test('exports single platform with header and platform prefix', () {
      final cookies = [
        PlatformCookie(
          platform: 'youtube',
          cookieString: '.youtube.com\tTRUE\t/\tTRUE\t1234567890\tSID\tabc123',
          savedAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 3, 1),
        ),
      ];

      final result = service.exportAllCookies(cookies);

      expect(result, startsWith('$header\n'));
      expect(result, contains('# Generated:'));
      expect(result, contains('# Platform: youtube'));
      expect(result, contains('.youtube.com\tTRUE\t/\tTRUE\t1234567890\tSID\tabc123'));
    });

    test('exports multiple platforms in order', () {
      final cookies = [
        PlatformCookie(
          platform: 'youtube',
          cookieString: 'yt_cookie_data',
          savedAt: DateTime(2026, 1, 1),
        ),
        PlatformCookie(
          platform: 'instagram',
          cookieString: 'ig_cookie_data',
          savedAt: DateTime(2026, 1, 1),
        ),
      ];

      final result = service.exportAllCookies(cookies);

      expect(result, contains('# Platform: youtube'));
      expect(result, contains('yt_cookie_data'));
      expect(result, contains('# Platform: instagram'));
      expect(result, contains('ig_cookie_data'));

      // youtube appears before instagram
      final ytIndex = result.indexOf('# Platform: youtube');
      final igIndex = result.indexOf('# Platform: instagram');
      expect(ytIndex, lessThan(igIndex));
    });

    test('exports empty list with only header', () {
      final result = service.exportAllCookies([]);

      expect(result, startsWith('$header\n'));
      expect(result, contains('# Generated:'));
      expect(result, isNot(contains('# Platform:')));
    });
  });

  group('importCookies', () {
    test('imports valid file with single platform', () async {
      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
.youtube.com\tTRUE\t/\tTRUE\t1234567890\tSID\tabc123
''';

      final imported = await service.importCookies(content);

      expect(imported, ['youtube']);
      expect(fakeRepo.savedCookies['youtube'],
          '.youtube.com\tTRUE\t/\tTRUE\t1234567890\tSID\tabc123');
    });

    test('imports valid file with multiple platforms', () async {
      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
yt_cookie_line1

# Platform: instagram
ig_cookie_line1
''';

      final imported = await service.importCookies(content);

      expect(imported, ['youtube', 'instagram']);
      expect(fakeRepo.savedCookies['youtube'], 'yt_cookie_line1');
      expect(fakeRepo.savedCookies['instagram'], 'ig_cookie_line1');
    });

    test('returns empty list for invalid file (no header)', () async {
      final content = '''Some random text
# Platform: youtube
cookie_data
''';

      final imported = await service.importCookies(content);

      expect(imported, isEmpty);
      expect(fakeRepo.savedCookies, isEmpty);
    });

    test('ignores comment lines and empty lines within platform block',
        () async {
      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
# This is a comment inside the block
.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc

.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN\txyz
''';

      final imported = await service.importCookies(content);

      expect(imported, ['youtube']);
      // Comment and empty lines are skipped; only actual cookie lines are saved
      final saved = fakeRepo.savedCookies['youtube']!;
      expect(saved, isNot(contains('# This is a comment')));
      expect(saved, contains('.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc'));
      expect(saved, contains('.youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN\txyz'));
    });

    test('saves cookies with 30-day expiry', () async {
      final before = DateTime.now();

      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
cookie_data_here
''';

      await service.importCookies(content);

      final after = DateTime.now();
      final expiry = fakeRepo.savedExpiries['youtube']!;

      // Expiry should be ~30 days from now
      final expectedMin = before.add(const Duration(days: 30));
      final expectedMax = after.add(const Duration(days: 30));
      expect(expiry.isAfter(expectedMin) || expiry.isAtSameMomentAs(expectedMin),
          isTrue);
      expect(expiry.isBefore(expectedMax) || expiry.isAtSameMomentAs(expectedMax),
          isTrue);
    });
  });

  group('isValidExportFile', () {
    test('returns true for valid content', () {
      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
cookie_data
''';

      expect(service.isValidExportFile(content), isTrue);
    });

    test('returns false for missing header', () {
      const content = '''# Some other header
# Platform: youtube
cookie_data
''';

      expect(service.isValidExportFile(content), isFalse);
    });

    test('returns false for missing platform prefix', () {
      final content = '''$header
# Generated: 2026-01-15T10:00:00.000

cookie_data_without_platform
''';

      expect(service.isValidExportFile(content), isFalse);
    });

    test('returns false for empty string', () {
      expect(service.isValidExportFile(''), isFalse);
    });

    test('returns true with leading/trailing whitespace around valid content',
        () {
      final content = '''
$header
# Generated: 2026-01-15T10:00:00.000

# Platform: youtube
cookie_data
''';

      // trim() removes leading newline, so header is first → valid
      expect(service.isValidExportFile(content), isTrue);
    });
  });
}
