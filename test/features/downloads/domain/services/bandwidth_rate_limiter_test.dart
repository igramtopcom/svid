import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/services/bandwidth_rate_limiter.dart';

void main() {
  group('BandwidthRateLimiter.computePerDownloadLimit', () {
    test('returns 0 when globalLimitKbps is 0 (unlimited)', () {
      expect(
        BandwidthRateLimiter.computePerDownloadLimit(
          globalLimitKbps: 0,
          activeCount: 3,
        ),
        0,
      );
    });

    test('returns 0 when activeCount is 0', () {
      expect(
        BandwidthRateLimiter.computePerDownloadLimit(
          globalLimitKbps: 1000,
          activeCount: 0,
        ),
        0,
      );
    });

    test('returns 0 when activeCount is negative', () {
      expect(
        BandwidthRateLimiter.computePerDownloadLimit(
          globalLimitKbps: 1000,
          activeCount: -1,
        ),
        0,
      );
    });

    test('divides evenly among 2 downloads: 1000 KB/s → 512000 B/s each', () {
      final result = BandwidthRateLimiter.computePerDownloadLimit(
        globalLimitKbps: 1000,
        activeCount: 2,
      );
      expect(result, 1000 * 1024 ~/ 2); // 512000
    });

    test('single download gets full allocation: 500 KB/s → 512000 B/s', () {
      final result = BandwidthRateLimiter.computePerDownloadLimit(
        globalLimitKbps: 500,
        activeCount: 1,
      );
      expect(result, 500 * 1024); // 512000
    });

    test('floors partial division: 1000 KB/s ÷ 3 = 341 KB = 349525 B/s', () {
      final result = BandwidthRateLimiter.computePerDownloadLimit(
        globalLimitKbps: 1000,
        activeCount: 3,
      );
      expect(result, 1000 * 1024 ~/ 3); // 349525
    });

    test('handles large limit: 10000 KB/s ÷ 5 = 2000 KB/s each', () {
      final result = BandwidthRateLimiter.computePerDownloadLimit(
        globalLimitKbps: 10000,
        activeCount: 5,
      );
      expect(result, 10000 * 1024 ~/ 5); // 2048000
    });

    test('1 KB/s ÷ 1 = 1024 B/s', () {
      final result = BandwidthRateLimiter.computePerDownloadLimit(
        globalLimitKbps: 1,
        activeCount: 1,
      );
      expect(result, 1024);
    });
  });

  group('BandwidthRateLimiter.computeWeightedLimit', () {
    test('returns 0 when globalLimitKbps is 0', () {
      expect(
        BandwidthRateLimiter.computeWeightedLimit(
          globalLimitKbps: 0,
          downloadPriority: 0,
          activeWeightSum: 1.0,
        ),
        0,
      );
    });

    test('returns 0 when activeWeightSum is 0', () {
      expect(
        BandwidthRateLimiter.computeWeightedLimit(
          globalLimitKbps: 1000,
          downloadPriority: 0,
          activeWeightSum: 0,
        ),
        0,
      );
    });

    test('high priority (1) gets 2× share vs normal (0)', () {
      // 3 downloads: 1 high + 1 normal + 1 low → weight sum = 2+1+0.5 = 3.5
      // high: 1000*1024 * 2.0 / 3.5 = 585142
      const kbps = 1000;
      final weightSum = BandwidthRateLimiter.totalWeightSum([1, 0, -1]);
      final highLimit = BandwidthRateLimiter.computeWeightedLimit(
        globalLimitKbps: kbps,
        downloadPriority: 1,
        activeWeightSum: weightSum,
      );
      final normalLimit = BandwidthRateLimiter.computeWeightedLimit(
        globalLimitKbps: kbps,
        downloadPriority: 0,
        activeWeightSum: weightSum,
      );
      final lowLimit = BandwidthRateLimiter.computeWeightedLimit(
        globalLimitKbps: kbps,
        downloadPriority: -1,
        activeWeightSum: weightSum,
      );
      expect(highLimit, greaterThan(normalLimit));
      expect(normalLimit, greaterThan(lowLimit));
      // high should be exactly 2× normal
      expect(highLimit, (normalLimit * 2).toInt().toDouble().round());
    });

    test('equal weights: 2 normal downloads → equal split', () {
      const kbps = 1000;
      final weightSum = BandwidthRateLimiter.totalWeightSum([0, 0]);
      final limit = BandwidthRateLimiter.computeWeightedLimit(
        globalLimitKbps: kbps,
        downloadPriority: 0,
        activeWeightSum: weightSum,
      );
      expect(limit, kbps * 1024 ~/ 2);
    });
  });

  group('BandwidthRateLimiter.totalWeightSum', () {
    test('empty list → 0', () => expect(BandwidthRateLimiter.totalWeightSum([]), 0));
    test('[0] → 1.0', () => expect(BandwidthRateLimiter.totalWeightSum([0]), 1.0));
    test('[1] → 2.0', () => expect(BandwidthRateLimiter.totalWeightSum([1]), 2.0));
    test('[-1] → 0.5', () => expect(BandwidthRateLimiter.totalWeightSum([-1]), 0.5));
    test('[1,0,-1] → 3.5', () => expect(BandwidthRateLimiter.totalWeightSum([1, 0, -1]), 3.5));
  });
}
