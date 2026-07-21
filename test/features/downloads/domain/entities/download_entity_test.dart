import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_error_code.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';

DownloadEntity _makeEntity({
  int id = 1,
  DownloadStatus status = DownloadStatus.pending,
  int totalBytes = 1000,
  int downloadedBytes = 0,
  int speed = 0,
  int? duration,
  int? viewCount,
  String? uploadDate,
  String? chaptersJson,
  String downloadMethod = 'ytdlp',
  String filename = 'video.mp4',
  String? errorMessage,
}) =>
    DownloadEntity(
      id: id,
      url: 'https://example.com/video',
      filename: filename,
      savePath: '/tmp',
      status: status,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      speed: speed,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      duration: duration,
      viewCount: viewCount,
      uploadDate: uploadDate,
      chaptersJson: chaptersJson,
      downloadMethod: downloadMethod,
      errorMessage: errorMessage,
    );

void main() {
  group('DownloadEntity', () {
    group('progress', () {
      test('returns 0 when totalBytes is 0', () {
        final entity = _makeEntity(totalBytes: 0);
        expect(entity.progress, 0.0);
      });

      test('returns 0 when totalBytes is negative', () {
        final entity = _makeEntity(totalBytes: -100);
        expect(entity.progress, 0.0);
      });

      test('calculates correct progress', () {
        final entity = _makeEntity(totalBytes: 1000, downloadedBytes: 500);
        expect(entity.progress, 0.5);
      });

      test('clamps progress to 1.0', () {
        final entity = _makeEntity(totalBytes: 100, downloadedBytes: 200);
        expect(entity.progress, 1.0);
      });

      test('progressPercentage is progress * 100', () {
        final entity = _makeEntity(totalBytes: 1000, downloadedBytes: 250);
        expect(entity.progressPercentage, 25.0);
      });
    });

    group('status helpers', () {
      test('isActive for downloading', () {
        expect(_makeEntity(status: DownloadStatus.downloading).isActive, isTrue);
      });

      test('isActive for pending', () {
        expect(_makeEntity(status: DownloadStatus.pending).isActive, isTrue);
      });

      test('isActive false for completed', () {
        expect(_makeEntity(status: DownloadStatus.completed).isActive, isFalse);
      });

      test('isCompleted', () {
        expect(_makeEntity(status: DownloadStatus.completed).isCompleted, isTrue);
      });

      test('isPaused', () {
        expect(_makeEntity(status: DownloadStatus.paused).isPaused, isTrue);
      });

      test('isFailed', () {
        expect(_makeEntity(status: DownloadStatus.failed).isFailed, isTrue);
      });

      test('isCancelled', () {
        expect(_makeEntity(status: DownloadStatus.cancelled).isCancelled, isTrue);
      });

      test('canResume when paused', () {
        expect(_makeEntity(status: DownloadStatus.paused).canResume, isTrue);
      });

      test('canResume when failed', () {
        expect(_makeEntity(status: DownloadStatus.failed).canResume, isTrue);
      });

      test('canResume false when downloading', () {
        expect(_makeEntity(status: DownloadStatus.downloading).canResume, isFalse);
      });

      test('canPause only when downloading', () {
        expect(_makeEntity(status: DownloadStatus.downloading).canPause, isTrue);
        expect(_makeEntity(status: DownloadStatus.paused).canPause, isFalse);
      });

      test('canCancel when pending, queued, active, paused, or waitingForNetwork', () {
        expect(_makeEntity(status: DownloadStatus.pending).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.queued).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.downloading).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.postProcessing).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.paused).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.waitingForNetwork).canCancel, isTrue);
        expect(_makeEntity(status: DownloadStatus.completed).canCancel, isFalse);
      });

      test('canRetry when failed or waitingForNetwork', () {
        expect(_makeEntity(status: DownloadStatus.failed).canRetry, isTrue);
        expect(_makeEntity(status: DownloadStatus.waitingForNetwork).canRetry, isTrue);
        expect(_makeEntity(status: DownloadStatus.completed).canRetry, isFalse);
      });

      test('isWaitingForNetwork', () {
        expect(_makeEntity(status: DownloadStatus.waitingForNetwork).isWaitingForNetwork, isTrue);
        expect(_makeEntity(status: DownloadStatus.failed).isWaitingForNetwork, isFalse);
      });

      test('canDelete when not active', () {
        expect(_makeEntity(status: DownloadStatus.completed).canDelete, isTrue);
        expect(_makeEntity(status: DownloadStatus.downloading).canDelete, isFalse);
      });
    });

    group('error code helpers', () {
      test('errorCode parses structured errorMessage', () {
        final entity = _makeEntity(
          errorMessage: 'networkTimeout:Connection timed out',
        );
        expect(entity.errorCode, DownloadErrorCode.networkTimeout);
      });

      test('errorCode returns null for unstructured errorMessage', () {
        final entity = _makeEntity(errorMessage: 'Just an error');
        expect(entity.errorCode, isNull);
      });

      test('errorCode returns null for null errorMessage', () {
        final entity = _makeEntity();
        expect(entity.errorCode, isNull);
      });

      test('errorDetail extracts raw detail', () {
        final entity = _makeEntity(
          errorMessage: 'diskFull:No space left on device',
        );
        expect(entity.errorDetail, 'No space left on device');
      });

      test('errorDetail returns original for legacy format', () {
        final entity = _makeEntity(errorMessage: 'Legacy error');
        expect(entity.errorDetail, 'Legacy error');
      });
    });

    group('file helpers', () {
      test('fileExtension returns extension', () {
        expect(_makeEntity(filename: 'video.mp4').fileExtension, '.mp4');
      });

      test('fileExtension handles no extension', () {
        expect(_makeEntity(filename: 'noext').fileExtension, '');
      });

      test('filenameWithoutExtension', () {
        expect(_makeEntity(filename: 'my.video.mp4').filenameWithoutExtension, 'my.video');
      });

      test('displayTitle uses title when available', () {
        final entity = _makeEntity().copyWith(title: 'My Video');
        expect(entity.displayTitle, 'My Video');
      });

      test('displayTitle falls back to filename', () {
        expect(_makeEntity(filename: 'video.mp4').displayTitle, 'video');
      });
    });

    group('formattedDuration', () {
      test('returns null when duration is null', () {
        expect(_makeEntity().formattedDuration, isNull);
      });

      test('returns null when duration is 0', () {
        expect(_makeEntity(duration: 0).formattedDuration, isNull);
      });

      test('formats minutes and seconds', () {
        expect(_makeEntity(duration: 754).formattedDuration, '12:34');
      });

      test('formats hours, minutes and seconds', () {
        expect(_makeEntity(duration: 5025).formattedDuration, '1:23:45');
      });

      test('formats short duration', () {
        expect(_makeEntity(duration: 5).formattedDuration, '0:05');
      });
    });

    group('formattedViewCount', () {
      test('returns null when viewCount is null', () {
        expect(_makeEntity().formattedViewCount, isNull);
      });

      test('formats billions', () {
        expect(_makeEntity(viewCount: 1500000000).formattedViewCount, '1.5B views');
      });

      test('formats millions', () {
        expect(_makeEntity(viewCount: 1200000).formattedViewCount, '1.2M views');
      });

      test('formats thousands', () {
        expect(_makeEntity(viewCount: 500000).formattedViewCount, '500.0K views');
      });

      test('formats small numbers', () {
        expect(_makeEntity(viewCount: 42).formattedViewCount, '42 views');
      });
    });

    group('parsedUploadDate', () {
      test('parses YYYYMMDD format', () {
        final date = _makeEntity(uploadDate: '20260115').parsedUploadDate;
        expect(date, DateTime(2026, 1, 15));
      });

      test('returns null for invalid format', () {
        expect(_makeEntity(uploadDate: 'invalid').parsedUploadDate, isNull);
      });

      test('returns null for null', () {
        expect(_makeEntity().parsedUploadDate, isNull);
      });
    });

    group('download method checks', () {
      test('isYtdlpDownload', () {
        expect(_makeEntity(downloadMethod: 'ytdlp').isYtdlpDownload, isTrue);
        expect(_makeEntity(downloadMethod: 'api').isYtdlpDownload, isFalse);
      });

      test('isGalleryDlDownload', () {
        expect(_makeEntity(downloadMethod: 'gallerydl').isGalleryDlDownload, isTrue);
      });
    });

    group('chapters', () {
      test('returns empty list when chaptersJson is null', () {
        expect(_makeEntity().chapters, isEmpty);
      });

      test('returns empty list when chaptersJson is empty', () {
        expect(_makeEntity(chaptersJson: '').chapters, isEmpty);
      });

      test('parses valid chapters JSON', () {
        final json = jsonEncode([
          {'title': 'Intro', 'startTime': 0.0, 'endTime': 30.0},
          {'title': 'Main', 'startTime': 30.0, 'endTime': 120.0},
        ]);
        final chapters = _makeEntity(chaptersJson: json).chapters;
        expect(chapters.length, 2);
        expect(chapters[0].title, 'Intro');
        expect(chapters[0].startTime, 0.0);
        expect(chapters[1].title, 'Main');
      });

      test('returns empty list for invalid JSON', () {
        expect(_makeEntity(chaptersJson: 'not json').chapters, isEmpty);
      });

      test('hasChapters returns true when chaptersJson is set', () {
        final json = jsonEncode([
          {'title': 'Ch1', 'startTime': 0.0, 'endTime': 10.0},
        ]);
        expect(_makeEntity(chaptersJson: json).hasChapters, isTrue);
      });
    });

    group('estimatedRemainingSeconds', () {
      test('returns null when speed is 0', () {
        final entity = _makeEntity(totalBytes: 1000, downloadedBytes: 500, speed: 0);
        expect(entity.estimatedRemainingSeconds, isNull);
      });

      test('returns null when remaining is 0', () {
        final entity = _makeEntity(totalBytes: 1000, downloadedBytes: 1000, speed: 100);
        expect(entity.estimatedRemainingSeconds, isNull);
      });

      test('calculates remaining time', () {
        final entity = _makeEntity(totalBytes: 1000, downloadedBytes: 500, speed: 100);
        expect(entity.estimatedRemainingSeconds, 5);
      });
    });
  });
}
