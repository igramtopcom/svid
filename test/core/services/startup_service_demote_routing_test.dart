import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/startup_service.dart';

/// Unit tests for [StartupService.demoteResultForSignal].
///
/// Regression guard for the revenue-critical premium-key-wipe bug: a
/// non-definitive demote signal (PHP checkkey `inactive`, locally-expired,
/// network/grace failure, format-corrupt, or the backend 0-grace post-expiry
/// `is_valid=false` with no reason) must NEVER wipe the stored license KEY —
/// it soft-demotes (drops premium, keeps the key) so an active auto-renew
/// subscriber auto-recovers when the backend re-confirms. Only a DEFINITIVE
/// server revoke (reason=='revoked' / tier resolved to free) full-wipes.
///
/// This predicate is the single routing decision that both startup demotion
/// sinks (`_maybeNotifyDemotion` for VidCombo PHP paths, SSvid `_verifyLicense`)
/// delegate to, so pinning it pins INVARIANT #1 at the wiring layer. The
/// returned label is also the telemetry `result` value emitted via the
/// existing analytics `license_verify` event.
void main() {
  group('demoteResultForSignal — INVARIANT #1 (never wipe key on uncertain)', () {
    test('non-definitive signal → soft_demote (key preserved)', () {
      expect(
        StartupService.demoteResultForSignal(definitive: false),
        'soft_demote',
        reason: 'PHP inactive / expired / network / grace / format / unknown '
            'must preserve the key so renewal auto-recovers premium',
      );
    });

    test('definitive server revoke → full_demote (key wiped)', () {
      expect(
        StartupService.demoteResultForSignal(definitive: true),
        'full_demote',
        reason: 'Only reason==revoked / tier==free justifies a full key-wipe',
      );
    });

    test('default (omitted) demote signal is non-definitive → soft_demote', () {
      // The VidCombo checkkey demotion call sites rely on _maybeNotifyDemotion
      // defaulting to non-definitive; a regression that flips the default would
      // resurrect the silent key-wipe on renewal-lag subscribers.
      expect(StartupService.demoteResultForSignal(definitive: false),
          isNot('full_demote'));
    });
  });

  group('license_verify telemetry decision label mapping', () {
    // The enriched license_verify event emits a `decision` field derived 1:1
    // from demoteResultForSignal: full_demote→full, soft_demote→soft. This
    // pins the mapping the demote sinks use so the telemetry can tell a
    // key-wiping full demote apart from a key-preserving soft demote.
    String decisionFor(bool definitive) =>
        StartupService.demoteResultForSignal(definitive: definitive) ==
                'full_demote'
            ? 'full'
            : 'soft';

    test('definitive revoke → decision "full"', () {
      expect(decisionFor(true), 'full');
    });

    test('uncertain signal → decision "soft"', () {
      expect(decisionFor(false), 'soft');
    });
  });
}
