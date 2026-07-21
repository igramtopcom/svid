import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/binaries/binary_type.dart';
import 'package:ssvid/core/binaries/binary_update_error_code.dart';
import 'package:ssvid/core/binaries/binary_update_history_service.dart';

void main() {
  group('BinaryUpdateHistoryService', () {
    late BinaryUpdateHistoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = BinaryUpdateHistoryService(prefs);
    });

    test('getHistory returns empty list initially', () {
      expect(service.getHistory(), isEmpty);
    });

    test('addSuccess stores and retrieves record', () {
      service.addSuccess(
        binaryType: BinaryType.ytDlp,
        oldVersion: '2025.02.01',
        newVersion: '2025.03.01',
      );

      final history = service.getHistory();
      expect(history, hasLength(1));
      expect(history.first.success, isTrue);
      expect(history.first.binaryType, BinaryType.ytDlp);
      expect(history.first.oldVersion, '2025.02.01');
      expect(history.first.newVersion, '2025.03.01');
      expect(history.first.errorCode, isNull);
    });

    test('addFailure stores error code and detail', () {
      service.addFailure(
        binaryType: BinaryType.ffmpeg,
        errorCode: BinaryUpdateErrorCode.networkOffline,
        oldVersion: '6.0',
        errorDetail: 'SocketException: Connection refused',
      );

      final history = service.getHistory();
      expect(history, hasLength(1));
      expect(history.first.success, isFalse);
      expect(history.first.binaryType, BinaryType.ffmpeg);
      expect(history.first.errorCode, BinaryUpdateErrorCode.networkOffline);
      expect(history.first.errorDetail, 'SocketException: Connection refused');
    });

    test('newest record is first', () {
      service.addSuccess(
        binaryType: BinaryType.ytDlp,
        newVersion: '1.0',
      );
      service.addSuccess(
        binaryType: BinaryType.ffmpeg,
        newVersion: '2.0',
      );

      final history = service.getHistory();
      expect(history, hasLength(2));
      expect(history[0].binaryType, BinaryType.ffmpeg);
      expect(history[1].binaryType, BinaryType.ytDlp);
    });

    test('circular buffer evicts oldest at maxRecords', () {
      for (int i = 0; i < BinaryUpdateHistoryService.maxRecords + 5; i++) {
        service.addSuccess(
          binaryType: BinaryType.ytDlp,
          newVersion: 'v$i',
        );
      }

      final history = service.getHistory();
      expect(history.length, BinaryUpdateHistoryService.maxRecords);
      // Newest should be last added
      expect(history.first.newVersion, 'v${BinaryUpdateHistoryService.maxRecords + 4}');
    });

    test('getHistoryForType filters correctly', () {
      service.addSuccess(binaryType: BinaryType.ytDlp, newVersion: '1.0');
      service.addSuccess(binaryType: BinaryType.ffmpeg, newVersion: '6.0');
      service.addFailure(
        binaryType: BinaryType.ytDlp,
        errorCode: BinaryUpdateErrorCode.httpError,
      );

      final ytdlpHistory = service.getHistoryForType(BinaryType.ytDlp);
      expect(ytdlpHistory, hasLength(2));

      final ffmpegHistory = service.getHistoryForType(BinaryType.ffmpeg);
      expect(ffmpegHistory, hasLength(1));

      final galleryHistory = service.getHistoryForType(BinaryType.galleryDl);
      expect(galleryHistory, isEmpty);
    });

    test('clear empties all records', () {
      service.addSuccess(binaryType: BinaryType.ytDlp, newVersion: '1.0');
      service.addSuccess(binaryType: BinaryType.ffmpeg, newVersion: '6.0');

      expect(service.getHistory(), hasLength(2));

      service.clear();
      expect(service.getHistory(), isEmpty);
    });

    test('JSON persistence round-trip', () async {
      service.addSuccess(
        binaryType: BinaryType.ytDlp,
        oldVersion: '2025.02.01',
        newVersion: '2025.03.01',
      );
      service.addFailure(
        binaryType: BinaryType.ffmpeg,
        errorCode: BinaryUpdateErrorCode.diskFull,
        errorDetail: 'ENOSPC',
      );

      // Create new service instance from same SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final service2 = BinaryUpdateHistoryService(prefs);

      final history = service2.getHistory();
      expect(history, hasLength(2));

      // Newest first (failure)
      expect(history[0].success, isFalse);
      expect(history[0].binaryType, BinaryType.ffmpeg);
      expect(history[0].errorCode, BinaryUpdateErrorCode.diskFull);
      expect(history[0].errorDetail, 'ENOSPC');

      // Oldest second (success)
      expect(history[1].success, isTrue);
      expect(history[1].binaryType, BinaryType.ytDlp);
      expect(history[1].oldVersion, '2025.02.01');
      expect(history[1].newVersion, '2025.03.01');
    });

    test('handles corrupted JSON gracefully', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BinaryUpdateHistoryService.storageKey, 'not-json');

      final service2 = BinaryUpdateHistoryService(prefs);
      expect(service2.getHistory(), isEmpty);
    });
  });
}
