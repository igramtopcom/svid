import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_priority.dart';

void main() {
  group('DownloadPriority.fromInt', () {
    test('maps 1 to high', () {
      expect(DownloadPriority.fromInt(1), DownloadPriority.high);
    });

    test('maps 0 to normal', () {
      expect(DownloadPriority.fromInt(0), DownloadPriority.normal);
    });

    test('maps -1 to low', () {
      expect(DownloadPriority.fromInt(-1), DownloadPriority.low);
    });

    test('unknown value defaults to normal', () {
      expect(DownloadPriority.fromInt(99), DownloadPriority.normal);
      expect(DownloadPriority.fromInt(-99), DownloadPriority.normal);
      expect(DownloadPriority.fromInt(2), DownloadPriority.normal);
    });
  });
}
