import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/services/startup_service.dart';
import 'package:svid/core/services/vidcombo/vidcombo_backend_adapter.dart';
import 'package:svid/features/premium/presentation/providers/payment_providers.dart';

/// Tests for the VidCombo user-deactivate tombstone + cache-clear helpers.
///
/// These helpers protect explicit user intent: when a user clicks
/// "Deactivate" we MUST (a) wipe the 15-minute premium cache so a
/// concurrent boot cannot re-promote them and (b) record a tombstone so
/// a leftover legacy `settings1.gs` does not silently re-import the key
/// on the next launch. The helpers are brand-guarded — SSvid builds
/// must never read/write the VidCombo-specific key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('clearVidComboCheckKeyCache', () {
    test('removes any persisted cache entry', () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.writeVidComboCheckKeyCache(
        prefs,
        VidComboCheckKeyResponse(
          licenseKey: 'A3B9EE755909C2E2836D4ED651834303',
          status: 'active',
          countFree: 10,
          plan: 'plan1',
          endDate: '2027-06-10',
        ),
        verifiedAt: DateTime.utc(2026, 5, 16, 9, 0),
      );

      expect(
        StartupService.readVidComboCheckKeyCache(
          prefs,
          now: DateTime.utc(2026, 5, 16, 9, 5),
        ),
        isNotNull,
        reason: 'precondition: cache populated',
      );

      await StartupService.clearVidComboCheckKeyCache(prefs);

      expect(
        StartupService.readVidComboCheckKeyCache(
          prefs,
          now: DateTime.utc(2026, 5, 16, 9, 5),
        ),
        isNull,
        reason: 'clear must wipe the cache entry',
      );
    });

    test('is idempotent — second clear on empty cache is a no-op', () async {
      final prefs = await SharedPreferences.getInstance();
      // Cache never written.
      await StartupService.clearVidComboCheckKeyCache(prefs);
      await StartupService.clearVidComboCheckKeyCache(prefs);
      expect(
        StartupService.readVidComboCheckKeyCache(
          prefs,
          now: DateTime.utc(2026, 5, 16),
        ),
        isNull,
      );
    });
  });

  group('VidCombo deactivate tombstone — VidCombo brand', () {
    setUp(() {
      BrandConfig.setForTest(Brand.vidcombo);
    });

    tearDown(() {
      BrandConfig.setForTest(null);
    });

    test('hasVidComboDeactivateTombstone returns false on a fresh install',
        () async {
      final prefs = await SharedPreferences.getInstance();
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isFalse);
    });

    test('setVidComboDeactivateTombstone persists across reads', () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.setVidComboDeactivateTombstone(prefs);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isTrue);
    });

    test(
        'clearVidComboDeactivateTombstone removes a previously set tombstone',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.setVidComboDeactivateTombstone(prefs);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isTrue);

      await StartupService.clearVidComboDeactivateTombstone(prefs);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isFalse);
    });

    test(
        'clearVidComboDeactivateTombstone is idempotent — clear without set is a no-op',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.clearVidComboDeactivateTombstone(prefs);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isFalse);
    });

    test(
        'set + clear cycle leaves SharedPreferences in clean state',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.setVidComboDeactivateTombstone(prefs);
      await StartupService.clearVidComboDeactivateTombstone(prefs);

      // Raw key absent after clear.
      expect(prefs.getBool('vidcombo_user_deactivated_v1'), isNull);
    });

    test(
        'set is idempotent — second call leaves the tombstone set, no flip',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.setVidComboDeactivateTombstone(prefs);
      await StartupService.setVidComboDeactivateTombstone(prefs);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isTrue);
    });
  });

  group('VidCombo deactivate tombstone — SSvid brand-guard', () {
    setUp(() {
      BrandConfig.setForTest(Brand.svid);
    });

    tearDown(() {
      BrandConfig.setForTest(null);
    });

    test('hasVidComboDeactivateTombstone is unconditionally false on SSvid',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // Even if the raw key were somehow set, SSvid must NEVER react to it.
      await prefs.setBool('vidcombo_user_deactivated_v1', true);
      expect(StartupService.hasVidComboDeactivateTombstone(prefs), isFalse);
    });

    test('setVidComboDeactivateTombstone is a no-op on SSvid', () async {
      final prefs = await SharedPreferences.getInstance();
      await StartupService.setVidComboDeactivateTombstone(prefs);
      // No raw write happened.
      expect(prefs.getBool('vidcombo_user_deactivated_v1'), isNull);
    });

    test(
        'clearVidComboDeactivateTombstone is a no-op on SSvid — preserves any pre-existing key',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // Simulate a stale VidCombo install state inherited across brands
      // (shouldn't happen in production, but the guard must be robust).
      await prefs.setBool('vidcombo_user_deactivated_v1', true);
      await StartupService.clearVidComboDeactivateTombstone(prefs);
      // SSvid clear must NOT touch the VidCombo-only key.
      expect(prefs.getBool('vidcombo_user_deactivated_v1'), isTrue);
    });
  });

  group('ActivationOutcome', () {
    // Sanity: ensure the public enum hasn't drifted. Marker-ordering
    // contract in payment_providers.dart depends on these two values
    // existing distinctly.
    test('has exactly success + failure cases', () {
      const all = {ActivationOutcome.success, ActivationOutcome.failure};
      expect(all.length, 2);
    });
  });
}
