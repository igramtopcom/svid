import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/services/startup_service.dart';
import 'package:svid/core/services/vidcombo/vidcombo_backend_adapter.dart';

/// Unit tests for the VidCombo checkkey.php bootstrap cache. This cache
/// is on the hot path of every VidCombo cold boot — if it silently
/// misses for a correct reason, the app takes an extra PHP round-trip;
/// if it silently hits for a WRONG reason (stale premium after an
/// upstream revoke), the user sees phantom premium.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  VidComboCheckKeyResponse activeResponse({
    String? licenseKey = 'A3B9EE755909C2E2836D4ED651834303',
    String? plan = 'plan1',
    String? endDate = '2027-06-10',
    int countFree = 10,
  }) {
    return VidComboCheckKeyResponse(
      licenseKey: licenseKey,
      status: 'active',
      countFree: countFree,
      plan: plan,
      endDate: endDate,
    );
  }

  group('VidCombo checkkey cache', () {
    test('returns a fresh premium cache inside the 15-minute TTL', () async {
      final prefs = await SharedPreferences.getInstance();
      final verifiedAt = DateTime.utc(2026, 4, 20, 3, 0);

      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        activeResponse(),
        verifiedAt: verifiedAt,
      );

      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: verifiedAt.add(const Duration(minutes: 10)),
      );

      expect(cached, isNotNull);
      expect(cached!.isPremium, isTrue);
      expect(cached.licenseKey, 'A3B9EE755909C2E2836D4ED651834303');
      expect(cached.plan, 'plan1');
      expect(cached.endDate, '2027-06-10');
      expect(cached.countFree, 10);
    });

    test('drops the cache once it crosses the 15-minute TTL boundary', () async {
      // Boundary-exact: exactly 15 minutes old → treated as stale so we
      // re-check upstream. "Near-stale" entries would lie on the wrong
      // side of a subscription revoke.
      final prefs = await SharedPreferences.getInstance();
      final verifiedAt = DateTime.utc(2026, 4, 20, 3, 0);

      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        activeResponse(),
        verifiedAt: verifiedAt,
      );

      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: verifiedAt.add(const Duration(minutes: 15)),
      );

      expect(cached, isNull);
    });

    test('returns null when no cache entry exists yet', () async {
      final prefs = await SharedPreferences.getInstance();
      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: DateTime.utc(2026, 4, 20, 3, 0),
      );
      expect(cached, isNull);
    });

    test('returns null for a malformed cache entry instead of throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vidcombo_checkkey_cache_v1', 'not-json');

      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: DateTime.utc(2026, 4, 20, 3, 0),
      );
      expect(cached, isNull);
    });

    test('returns null when verified_at_ms is missing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vidcombo_checkkey_cache_v1',
        '{"status":"active","count_free":10,"plan":"plan1"}',
      );

      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: DateTime.utc(2026, 4, 20, 3, 0),
      );
      expect(cached, isNull);
    });

    test('overwrites an existing cache entry on a new write', () async {
      final prefs = await SharedPreferences.getInstance();
      final t0 = DateTime.utc(2026, 4, 20, 3, 0);

      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        activeResponse(plan: 'plan1', endDate: '2027-06-10'),
        verifiedAt: t0,
      );
      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        activeResponse(plan: 'plan2', endDate: '2028-06-10'),
        verifiedAt: t0.add(const Duration(minutes: 3)),
      );

      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: t0.add(const Duration(minutes: 5)),
      );

      expect(cached, isNotNull);
      expect(cached!.plan, 'plan2');
      expect(cached.endDate, '2028-06-10');
    });

    test('write → read round-trip preserves null-optional fields', () async {
      // plan, endDate, licenseKey can all legally be null in the PHP
      // response. Serialisation must survive that.
      final prefs = await SharedPreferences.getInstance();
      final t0 = DateTime.utc(2026, 4, 20, 3, 0);
      final response = VidComboCheckKeyResponse(
        licenseKey: null,
        status: 'active',
        countFree: 5,
        plan: null,
        endDate: null,
      );

      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        response,
        verifiedAt: t0,
      );
      final cached = StartupService.readVidComboCheckKeyCache(
        prefs,
        now: t0.add(const Duration(seconds: 30)),
      );

      expect(cached, isNotNull);
      expect(cached!.status, 'active');
      expect(cached.licenseKey, isNull);
      expect(cached.plan, isNull);
      expect(cached.endDate, isNull);
      expect(cached.countFree, 5);
    });
  });

  /// Pure decision tests for the cache-hit background refresh. Guards the
  /// "phantom premium after remote revoke" failure mode that bit Cache v1.
  group('VidCombo background-refresh decision', () {
    test('writes fresh cache when backend re-confirms premium', () {
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: true,
        freshMessage: null,
        storedLicenseKey: 'A3B9EE755909C2E2836D4ED651834303',
        isStoredKeyGoBackend: false,
        goBackendStillValid: false,
      );
      expect(decision.action, BackgroundRefreshAction.writeFreshCache);
    });

    test('demotes when PHP says inactive and license is PHP-format', () {
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: false,
        freshMessage: 'Subscription expired',
        storedLicenseKey: 'A3B9EE755909C2E2836D4ED651834303',
        isStoredKeyGoBackend: false,
        goBackendStillValid: false,
      );
      expect(decision.action, BackgroundRefreshAction.demote);
      expect(decision.serverMessage, 'Subscription expired');
      expect(decision.hadGoLicense, isFalse);
    });

    test('keeps cache when PHP says inactive but Go license still valid', () {
      // A Stripe-issued Go-backend license is unknown to PHP; we MUST NOT
      // demote a still-valid Stripe customer just because the PHP cache
      // refresh disagrees.
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: false,
        freshMessage: 'Unknown key',
        storedLicenseKey: 'VIDCOMBO-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-1111-2222',
        isStoredKeyGoBackend: true,
        goBackendStillValid: true,
      );
      expect(decision.action, BackgroundRefreshAction.keepCache);
    });

    test('demotes when PHP AND Go both say inactive on a Go-format key', () {
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: false,
        freshMessage: 'Subscription cancelled',
        storedLicenseKey: 'VIDCOMBO-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-1111-2222',
        isStoredKeyGoBackend: true,
        goBackendStillValid: false,
      );
      expect(decision.action, BackgroundRefreshAction.demote);
      expect(decision.hadGoLicense, isTrue);
      expect(decision.serverMessage, 'Subscription cancelled');
    });

    test('demotes with hadGoLicense=false when no key is stored at all', () {
      // Edge case: cache existed (so user was once premium) but the stored
      // license_key was somehow cleared between launches. Treat as PHP-only
      // signal — demote if PHP says inactive.
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: false,
        freshMessage: null,
        storedLicenseKey: null,
        isStoredKeyGoBackend: false,
        goBackendStillValid: false,
      );
      expect(decision.action, BackgroundRefreshAction.demote);
      expect(decision.hadGoLicense, isFalse);
    });

    test(
        'fresh-is-premium short-circuits even if the Go check would say invalid',
        () {
      // Defensive: a stale Go-validity bit must not flip a confirmed-premium
      // PHP response into a demotion. PHP active is the authoritative signal.
      final decision = StartupService.decideBackgroundRefreshAction(
        freshIsPremium: true,
        freshMessage: null,
        storedLicenseKey: 'VIDCOMBO-AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-1111-2222',
        isStoredKeyGoBackend: true,
        goBackendStillValid: false,
      );
      expect(decision.action, BackgroundRefreshAction.writeFreshCache);
    });
  });
}
