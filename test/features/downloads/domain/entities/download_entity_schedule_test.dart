import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';

DownloadEntity _base({
  DownloadStatus status = DownloadStatus.pending,
  DateTime? scheduledAt,
}) {
  final now = DateTime(2026, 3, 1, 12, 0);
  return DownloadEntity(
    id: 1,
    url: 'https://example.com/video',
    filename: 'video.mp4',
    savePath: '/downloads',
    status: status,
    totalBytes: 1000,
    downloadedBytes: 0,
    speed: 0,
    createdAt: now,
    updatedAt: now,
    scheduledAt: scheduledAt,
  );
}

void main() {
  group('DownloadEntity.scheduledAt', () {
    test('isScheduled is false when scheduledAt is null', () {
      expect(_base().isScheduled, isFalse);
    });

    test('isScheduled is true when pending + scheduledAt set', () {
      final d = _base(scheduledAt: DateTime(2026, 3, 2, 8, 0));
      expect(d.isScheduled, isTrue);
    });

    test('isScheduled is false for non-pending status even with scheduledAt', () {
      final d = _base(
        status: DownloadStatus.downloading,
        scheduledAt: DateTime(2026, 3, 2, 8, 0),
      );
      expect(d.isScheduled, isFalse);
    });

    test('isScheduled is false for completed status', () {
      final d = _base(
        status: DownloadStatus.completed,
        scheduledAt: DateTime(2026, 3, 2, 8, 0),
      );
      expect(d.isScheduled, isFalse);
    });

    test('copyWith preserves scheduledAt when not overridden', () {
      final original = _base(scheduledAt: DateTime(2026, 3, 2, 8, 0));
      final copy = original.copyWith(speed: 100);
      expect(copy.scheduledAt, original.scheduledAt);
    });

    test('copyWith can clear scheduledAt', () {
      final original = _base(scheduledAt: DateTime(2026, 3, 2, 8, 0));
      final copy = original.copyWith(scheduledAt: null);
      expect(copy.scheduledAt, isNull);
      expect(copy.isScheduled, isFalse);
    });
  });
}
