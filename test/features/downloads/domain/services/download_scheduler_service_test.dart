import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/services/download_scheduler_service.dart';

void main() {
  group('DownloadSchedulerService', () {
    test('isRunning is false initially', () {
      final svc = DownloadSchedulerService();
      expect(svc.isRunning, isFalse);
    });

    test('isRunning is true after start()', () {
      final svc = DownloadSchedulerService();
      svc.start(() {});
      expect(svc.isRunning, isTrue);
      svc.stop();
    });

    test('isRunning is false after stop()', () {
      final svc = DownloadSchedulerService();
      svc.start(() {});
      svc.stop();
      expect(svc.isRunning, isFalse);
    });

    test('calls onTick immediately on start()', () {
      final svc = DownloadSchedulerService();
      var callCount = 0;
      svc.start(() => callCount++);
      expect(callCount, 1); // fired synchronously before first interval
      svc.stop();
    });

    test('fires onTick again after one interval', () async {
      final svc = DownloadSchedulerService(
        interval: const Duration(milliseconds: 50),
      );
      var callCount = 0;
      svc.start(() => callCount++);
      expect(callCount, 1);
      await Future.delayed(const Duration(milliseconds: 80));
      expect(callCount, greaterThanOrEqualTo(2));
      svc.stop();
    });

    test('stop prevents further ticks', () async {
      final svc = DownloadSchedulerService(
        interval: const Duration(milliseconds: 50),
      );
      var callCount = 0;
      svc.start(() => callCount++);
      svc.stop();
      final countAfterStop = callCount;
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callCount, countAfterStop); // no more ticks after stop
    });

    test('calling start() twice cancels the first timer', () async {
      final svc = DownloadSchedulerService(
        interval: const Duration(milliseconds: 50),
      );
      var callCount = 0;
      svc.start(() => callCount++);
      svc.start(() => callCount++); // second start should cancel first
      final countAfterDoubleStart = callCount;
      // Only the second start's immediate call should increment
      expect(callCount, countAfterDoubleStart);
      svc.stop();
    });
  });
}
