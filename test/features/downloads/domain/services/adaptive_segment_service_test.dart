// Task 84.5 — unit tests for AdaptiveSegmentService
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/services/adaptive_segment_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // computeOptimalSegments — bandwidth → segment tier
  // ---------------------------------------------------------------------------

  group('computeOptimalSegments', () {
    test('0 bps (no signal) → 2 segments (< 5 MB/s tier)', () {
      expect(AdaptiveSegmentService.computeOptimalSegments(0), equals(2));
    });

    test('1 MB/s → 2 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(1 * 1024 * 1024),
        equals(2),
      );
    });

    test('just below 5 MB/s → 2 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(5 * 1024 * 1024 - 1),
        equals(2),
      );
    });

    test('exactly 5 MB/s → 4 segments (boundary)', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(5 * 1024 * 1024),
        equals(4),
      );
    });

    test('10 MB/s → 4 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(10 * 1024 * 1024),
        equals(4),
      );
    });

    test('just below 20 MB/s → 4 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(20 * 1024 * 1024 - 1),
        equals(4),
      );
    });

    test('exactly 20 MB/s → 8 segments (boundary)', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(20 * 1024 * 1024),
        equals(8),
      );
    });

    test('35 MB/s → 8 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(35 * 1024 * 1024),
        equals(8),
      );
    });

    test('just below 50 MB/s → 8 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(50 * 1024 * 1024 - 1),
        equals(8),
      );
    });

    test('exactly 50 MB/s → 16 segments (boundary)', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(50 * 1024 * 1024),
        equals(16),
      );
    });

    test('100 MB/s → 16 segments', () {
      expect(
        AdaptiveSegmentService.computeOptimalSegments(100 * 1024 * 1024),
        equals(16),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // logMessage
  // ---------------------------------------------------------------------------

  group('logMessage', () {
    test('includes segment count', () {
      final msg = AdaptiveSegmentService.logMessage(8, 35 * 1024 * 1024);
      expect(msg, contains('8'));
    });

    test('includes "Adaptive segments" prefix', () {
      final msg = AdaptiveSegmentService.logMessage(4, 10 * 1024 * 1024);
      expect(msg, startsWith('Adaptive segments:'));
    });

    test('includes rounded Mbps bandwidth', () {
      // 35 MB/s = 35 Mbps in the log
      final msg = AdaptiveSegmentService.logMessage(8, 35 * 1024 * 1024);
      expect(msg, contains('35 Mbps'));
    });

    test('format example: "Adaptive segments: 8 (bandwidth: 35 Mbps)"', () {
      final msg = AdaptiveSegmentService.logMessage(8, 35 * 1024 * 1024);
      expect(msg, equals('Adaptive segments: 8 (bandwidth: 35 Mbps)'));
    });
  });

  // ---------------------------------------------------------------------------
  // hasBandwidthChangedSignificantly
  // ---------------------------------------------------------------------------

  group('hasBandwidthChangedSignificantly', () {
    test('0 initial → always false (avoid divide-by-zero)', () {
      expect(
        AdaptiveSegmentService.hasBandwidthChangedSignificantly(0, 50 * 1024 * 1024),
        isFalse,
      );
    });

    test('60 % drop → true', () {
      final initial = 10 * 1024 * 1024;
      final current = 4 * 1024 * 1024; // 60% drop → ratio 0.6 > 0.5
      expect(
        AdaptiveSegmentService.hasBandwidthChangedSignificantly(initial, current),
        isTrue,
      );
    });

    test('49 % drop → false (below threshold)', () {
      final initial = 100 * 1024 * 1024;
      final current = (initial * 0.51).toInt(); // ~49% drop
      expect(
        AdaptiveSegmentService.hasBandwidthChangedSignificantly(initial, current),
        isFalse,
      );
    });

    test('200 % increase → true', () {
      final initial = 5 * 1024 * 1024;
      final current = 15 * 1024 * 1024; // 200% increase
      expect(
        AdaptiveSegmentService.hasBandwidthChangedSignificantly(initial, current),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // shouldAdjustSegments
  // ---------------------------------------------------------------------------

  group('shouldAdjustSegments', () {
    test('same tier despite >50% fluctuation → false', () {
      // Both 10 MB/s and 18 MB/s are in the 4-segment tier, but >50% change
      // Actually 10→18 is only 80% which is >50% but same tier — should be false
      // Wait: |18-10|/10 = 0.8 > 0.5 → significant, BUT both map to 4 segs → false
      // Let me check: 10 MB/s → 4 segs, 18 MB/s → 4 segs, same tier → false
      final initial = 10 * 1024 * 1024;
      final current = 18 * 1024 * 1024;
      expect(
        AdaptiveSegmentService.shouldAdjustSegments(initial, current),
        isFalse,
        reason: 'Both 10 and 18 MB/s map to 4 segments — no tier change',
      );
    });

    test('crosses tier boundary with >50% change → true', () {
      // 5 MB/s (4 segs) → 25 MB/s (8 segs), 400% increase → true
      final initial = 5 * 1024 * 1024;
      final current = 25 * 1024 * 1024;
      expect(
        AdaptiveSegmentService.shouldAdjustSegments(initial, current),
        isTrue,
      );
    });

    test('crosses tier boundary but <50% change → false', () {
      // 19 MB/s (4 segs) → 21 MB/s (8 segs) — ~10% change, tier changes but not significant
      final initial = 19 * 1024 * 1024;
      final current = 21 * 1024 * 1024;
      expect(
        AdaptiveSegmentService.shouldAdjustSegments(initial, current),
        isFalse,
        reason: 'Change < 50% — not considered significant enough to readjust',
      );
    });

    test('initial 0 → false (no signal)', () {
      expect(
        AdaptiveSegmentService.shouldAdjustSegments(0, 100 * 1024 * 1024),
        isFalse,
      );
    });
  });
}
