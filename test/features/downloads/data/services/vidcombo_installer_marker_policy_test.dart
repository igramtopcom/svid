import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/services/vidcombo_installer_marker_policy.dart';

/// Unit tests for the pure decision logic that governs the VidCombo
/// installer-marker handshake. These tests cover the corner cases that
/// ship in Windows-only code — the same scenarios that cannot be
/// exercised by runtime verification from a macOS build host.
void main() {
  MarkerObservation obs({
    bool markerExists = true,
    int? markerMtimeMs = 1000,
    int? lastProcessedMtimeMs,
    int currentFailCount = 0,
    bool deleteSucceeded = false,
  }) {
    return MarkerObservation(
      markerExists: markerExists,
      markerMtimeMs: markerMtimeMs,
      lastProcessedMtimeMs: lastProcessedMtimeMs,
      currentFailCount: currentFailCount,
      deleteSucceeded: deleteSucceeded,
    );
  }

  group('decideInstallerMarkerAction — no marker on disk', () {
    test('returns skip when the marker file is absent', () {
      final d = decideInstallerMarkerAction(obs(markerExists: false));
      expect(d.skip, isTrue);
      expect(d.resetState, isFalse);
      expect(d.persistProcessedMtime, isNull);
      expect(d.nextFailCount, isNull);
      expect(d.clearFailCount, isFalse);
    });
  });

  group('decideInstallerMarkerAction — idempotency guard', () {
    test(
      'skips entirely when the marker mtime matches what we already processed',
      () {
        // THIS is the case that fixes the infinite-reset loop introduced
        // when a permanently-locked marker was force-accepted: the file
        // is still on disk with the same mtime, so every subsequent
        // launch must treat it as already processed.
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 12345,
          lastProcessedMtimeMs: 12345,
          currentFailCount: 99, // even a huge counter must not fire
          deleteSucceeded: false,
        ));
        expect(d.skip, isTrue);
        expect(d.resetState, isFalse);
        expect(d.persistProcessedMtime, isNull);
        expect(d.nextFailCount, isNull);
        expect(d.clearFailCount, isFalse);
      },
    );

    test(
      'does NOT skip when a new installer run produced a marker with a '
      'different mtime from the one we previously fingerprinted',
      () {
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 22222,
          lastProcessedMtimeMs: 11111,
          deleteSucceeded: true,
        ));
        expect(d.skip, isFalse);
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, 22222);
      },
    );

    test(
      'does NOT skip when we failed to stat the marker (markerMtimeMs=null) '
      'so fingerprint comparison cannot short-circuit',
      () {
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: null,
          lastProcessedMtimeMs: 12345,
          deleteSucceeded: true,
        ));
        expect(d.skip, isFalse);
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, isNull);
      },
    );
  });

  group('decideInstallerMarkerAction — happy path', () {
    test(
      'first-time process with successful delete resets state and '
      'fingerprints the mtime',
      () {
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 555,
          lastProcessedMtimeMs: null,
          currentFailCount: 0,
          deleteSucceeded: true,
        ));
        expect(d.skip, isFalse);
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, 555);
        expect(d.clearFailCount, isTrue);
        expect(d.nextFailCount, isNull);
      },
    );

    test('successful delete clears a non-zero fail counter', () {
      final d = decideInstallerMarkerAction(obs(
        markerExists: true,
        markerMtimeMs: 555,
        currentFailCount: 2,
        deleteSucceeded: true,
      ));
      expect(d.clearFailCount, isTrue);
      expect(d.nextFailCount, isNull);
    });
  });

  group('decideInstallerMarkerAction — anti-loop on persistent delete failure', () {
    test(
      'first failure: increments the counter, does NOT reset state yet '
      '(give Defender / user another launch to release the lock)',
      () {
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 100,
          currentFailCount: 0,
          deleteSucceeded: false,
        ));
        expect(d.skip, isFalse);
        expect(d.resetState, isFalse);
        expect(d.persistProcessedMtime, isNull);
        expect(d.nextFailCount, 1);
        expect(d.clearFailCount, isFalse);
      },
    );

    test('second failure: counter bumps to 2, still no reset', () {
      final d = decideInstallerMarkerAction(obs(
        markerExists: true,
        markerMtimeMs: 100,
        currentFailCount: 1,
        deleteSucceeded: false,
      ));
      expect(d.resetState, isFalse);
      expect(d.nextFailCount, 2);
    });

    test(
      'third failure: counter reaches threshold so we force-accept — '
      'state IS reset and the mtime is fingerprinted so the stuck '
      'marker will not trigger another reset next launch',
      () {
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 100,
          currentFailCount: 2,
          deleteSucceeded: false,
        ));
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, 100);
        expect(d.nextFailCount, 3);
      },
    );

    test(
      'the loop em introduced in Wave 5.2 v1 CANNOT recur: fourth / fifth '
      'failure with the same mtime is caught by the idempotency guard '
      'and skipped entirely',
      () {
        final stateAfterForce = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 100,
          lastProcessedMtimeMs: 100, // fingerprint persisted by prior launch
          currentFailCount: 3,
          deleteSucceeded: false,
        ));
        expect(stateAfterForce.skip, isTrue);
        expect(stateAfterForce.resetState, isFalse);
        expect(stateAfterForce.nextFailCount, isNull);
      },
    );

    test(
      'custom threshold lets tests exercise the force-accept branch '
      'without needing 3 consecutive observations',
      () {
        final d = decideInstallerMarkerAction(
          obs(
            markerExists: true,
            markerMtimeMs: 100,
            currentFailCount: 0,
            deleteSucceeded: false,
          ),
          forceAcceptThreshold: 1,
        );
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, 100);
        expect(d.nextFailCount, 1);
      },
    );
  });

  group('decideInstallerMarkerAction — new installer after force-accept', () {
    test(
      'when a fresh installer writes a new marker (new mtime) over a '
      'previously-force-accepted one, we process it again',
      () {
        // Simulate: prior launch force-accepted mtime=100, then user
        // re-ran the installer which wrote a new marker with mtime=200.
        final d = decideInstallerMarkerAction(obs(
          markerExists: true,
          markerMtimeMs: 200,
          lastProcessedMtimeMs: 100,
          currentFailCount: 3, // stale counter from prior round
          deleteSucceeded: true,
        ));
        expect(d.skip, isFalse);
        expect(d.resetState, isTrue);
        expect(d.persistProcessedMtime, 200);
        expect(d.clearFailCount, isTrue);
      },
    );
  });
}
