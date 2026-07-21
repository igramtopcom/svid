// DL-016 — missing-binary self-heal contract (06-11 production wave:
// ytdlpBinaryMissing 40 rows/day, 94/95 Windows, release-correlated).
//
// Locks the four mechanisms of the fix:
//  1. Availability is verified ON DISK — a binary deleted after init
//     (AV retroactive quarantine, failed OTA rollback) must invalidate
//     the stale `_cachedPaths` entry instead of feeding spawn sites a
//     dead path (the old cache-only `isAvailable` was the root).
//  2. An orphaned `.bak` (stranded by a failed `updateBinarySafely`
//     rollback) is adopted at startup — field devices self-heal.
//  3. Repair attempts are CAPPED — after 3 consecutive failures the
//     repair short-circuits so callers surface terminal guidance
//     instead of looping download→quarantine→download forever.
//  4. Repair outcomes emit telemetry — the per-device event sequence is
//     the instrument that confirms/refutes the AV-quarantine hypothesis.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/binaries/binary_manager.dart';
import 'package:svid/core/binaries/binary_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;
  late List<(String, Map<String, String>)> events;

  Future<File> seedYtdlp({String suffix = ''}) async {
    final binDir = Directory(p.join(tempSupport.path, 'bin'));
    await binDir.create(recursive: true);
    final file = File(
      p.join(binDir.path, '${BinaryType.ytDlp.filename}$suffix'),
    );
    // ≥ minHealthyBytes (1.5MB) so _validateBinary passes the size floor.
    await file.writeAsBytes(List.filled(2 * 1024 * 1024, 0));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', file.path]);
    }
    return file;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempSupport = await Directory.systemTemp.createTemp('bm_dl016_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempSupport.path;
            }
            return null;
          },
        );
    BinaryManager.resetForTest();
    events = [];
    BinaryManager.telemetryListener =
        (event, props) => events.add((event, props));
  });

  tearDown(() async {
    BinaryManager.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  group('DL-016: disk-verified availability', () {
    test('isAvailable/getBinaryPath detect a binary that vanished after '
        'init and invalidate the stale cache', () async {
      final binary = await seedYtdlp();
      final manager = BinaryManager();
      await manager.initialize();

      expect(await manager.isAvailable(BinaryType.ytDlp), isTrue);
      expect(await manager.getBinaryPath(BinaryType.ytDlp), binary.path);

      // Simulate AV quarantine / failed rollback: file gone post-init.
      await binary.delete();

      expect(
        await manager.isAvailable(BinaryType.ytDlp),
        isFalse,
        reason: 'cache-only availability was the DL-016 root cause',
      );
      expect(await manager.getBinaryPath(BinaryType.ytDlp), isNull);
      expect(
        events.any((e) => e.$1 == 'binary_missing_detected'),
        isTrue,
        reason: 'missing-detection must be measurable fleet-wide',
      );
    });
  });

  group('DL-016: disk-verified getMissingBinaries (Codex review catch)', () {
    test('a binary that vanished after init is reported missing by '
        'getMissingBinaries/allBinariesAvailable, not stale-healthy', () async {
      final binary = await seedYtdlp();
      final manager = BinaryManager();
      await manager.initialize();

      expect(
        await manager.getMissingBinaries(),
        isNot(contains(BinaryType.ytDlp)),
      );

      await binary.delete();

      expect(
        await manager.getMissingBinaries(),
        contains(BinaryType.ytDlp),
        reason:
            'cache-only read here let the setup screen report a quarantined '
            'binary as healthy',
      );
      expect(await manager.allBinariesAvailable(), isFalse);
    });
  });

  group('DL-016: orphaned .bak adoption', () {
    test('startup promotes a lone .bak to the live binary', () async {
      await seedYtdlp(suffix: '.bak');
      final manager = BinaryManager();
      await manager.initialize();

      expect(
        await manager.isAvailable(BinaryType.ytDlp),
        isTrue,
        reason:
            'a failed updateBinarySafely rollback strands users with only '
            'the .bak — startup adoption is the field rescue',
      );
      expect(events.any((e) => e.$1 == 'binary_bak_adopted'), isTrue);
    });
  });

  group('DL-016: capped repair', () {
    test('repair short-circuits to false once the failure streak hits the '
        'cap — no download attempt, outcome=exhausted', () async {
      final manager = BinaryManager();
      await manager.initialize(); // no binary seeded → missing

      BinaryManager.setRepairFailureStreakForTest(BinaryType.ytDlp, 3);

      final repaired = await manager.triggerRepair(BinaryType.ytDlp);

      expect(repaired, isFalse);
      final outcome = events.lastWhere(
        (e) => e.$1 == 'binary_repair_outcome',
      );
      expect(outcome.$2['outcome'], 'exhausted');
    });

    test('healthy binary resets the failure streak (outcome='
        'already_healthy)', () async {
      await seedYtdlp();
      final manager = BinaryManager();
      await manager.initialize();

      BinaryManager.setRepairFailureStreakForTest(BinaryType.ytDlp, 2);

      final repaired = await manager.triggerRepair(BinaryType.ytDlp);

      expect(repaired, isTrue);
      expect(
        BinaryManager.repairFailureStreakForTest(BinaryType.ytDlp),
        0,
        reason: 'success/healthy must clear the streak so a later genuine '
            'failure gets its full attempt budget',
      );
      final outcome = events.lastWhere(
        (e) => e.$1 == 'binary_repair_outcome',
      );
      expect(outcome.$2['outcome'], 'already_healthy');
    });
  });
}
