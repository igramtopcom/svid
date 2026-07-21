import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';

void main() {
  group('DownloadStatus', () {
    group('toDbString', () {
      test('converts all statuses to their name', () {
        for (final status in DownloadStatus.values) {
          expect(status.toDbString(), status.name);
        }
      });
    });

    group('fromDbString', () {
      test('parses valid status strings', () {
        expect(DownloadStatus.fromDbString('pending'), DownloadStatus.pending);
        expect(DownloadStatus.fromDbString('downloading'), DownloadStatus.downloading);
        expect(DownloadStatus.fromDbString('completed'), DownloadStatus.completed);
        expect(DownloadStatus.fromDbString('failed'), DownloadStatus.failed);
        expect(DownloadStatus.fromDbString('paused'), DownloadStatus.paused);
        expect(DownloadStatus.fromDbString('cancelled'), DownloadStatus.cancelled);
        expect(DownloadStatus.fromDbString('queued'), DownloadStatus.queued);
        expect(DownloadStatus.fromDbString('postProcessing'), DownloadStatus.postProcessing);
        expect(DownloadStatus.fromDbString('waitingForNetwork'), DownloadStatus.waitingForNetwork);
      });

      test('returns pending for unknown strings', () {
        expect(DownloadStatus.fromDbString('invalid'), DownloadStatus.pending);
        expect(DownloadStatus.fromDbString(''), DownloadStatus.pending);
      });

      test('roundtrips correctly', () {
        for (final status in DownloadStatus.values) {
          expect(DownloadStatus.fromDbString(status.toDbString()), status);
        }
      });
    });

    group('isTerminal', () {
      test('completed is terminal', () {
        expect(DownloadStatus.completed.isTerminal, isTrue);
      });

      test('failed is terminal', () {
        expect(DownloadStatus.failed.isTerminal, isTrue);
      });

      test('cancelled is terminal', () {
        expect(DownloadStatus.cancelled.isTerminal, isTrue);
      });

      test('downloading is not terminal', () {
        expect(DownloadStatus.downloading.isTerminal, isFalse);
      });

      test('pending is not terminal', () {
        expect(DownloadStatus.pending.isTerminal, isFalse);
      });

      test('waitingForNetwork is not terminal', () {
        expect(DownloadStatus.waitingForNetwork.isTerminal, isFalse);
      });
    });

    group('isActive', () {
      test('pending is active', () {
        expect(DownloadStatus.pending.isActive, isTrue);
      });

      test('queued is active', () {
        expect(DownloadStatus.queued.isActive, isTrue);
      });

      test('downloading is active', () {
        expect(DownloadStatus.downloading.isActive, isTrue);
      });

      test('postProcessing is active', () {
        expect(DownloadStatus.postProcessing.isActive, isTrue);
      });

      test('paused is not active', () {
        expect(DownloadStatus.paused.isActive, isFalse);
      });

      test('completed is not active', () {
        expect(DownloadStatus.completed.isActive, isFalse);
      });

      test('failed is not active', () {
        expect(DownloadStatus.failed.isActive, isFalse);
      });

      test('waitingForNetwork is not active', () {
        expect(DownloadStatus.waitingForNetwork.isActive, isFalse);
      });
    });

    group('displayLabel', () {
      // displayLabel now resolves via AppLocalizations (i18n keys). In a
      // unit-test context easy_localization is not initialized, so .tr()
      // returns the key path itself ("downloadStatus.pending"). Tests
      // assert the contract — every status maps to a non-empty key —
      // not the literal English string.
      test('every status maps to a non-empty key', () {
        for (final status in DownloadStatus.values) {
          expect(status.displayLabel, isNotEmpty);
        }
      });

      test('every status maps to a unique key', () {
        final labels = DownloadStatus.values.map((s) => s.displayLabel).toSet();
        expect(labels.length, DownloadStatus.values.length);
      });
    });
  });
}
