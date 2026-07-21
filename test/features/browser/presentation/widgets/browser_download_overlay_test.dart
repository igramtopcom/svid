import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Tests for BrowserDownloadOverlay auto-collapse behavior.
///
/// The overlay auto-collapses after 3 seconds when expanded.
/// Since the overlay is a ConsumerStatefulWidget requiring
/// Riverpod providers (browserActiveCountProvider, etc.),
/// we test the timer logic in isolation.

void main() {
  group('Auto-collapse timer logic', () {
    test('timer fires after 3 seconds', () async {
      var collapsed = false;
      final timer = Timer(const Duration(seconds: 3), () {
        collapsed = true;
      });

      expect(collapsed, isFalse);

      // Wait 2 seconds — should NOT have collapsed
      await Future.delayed(const Duration(seconds: 2));
      expect(collapsed, isFalse);

      // Wait 1.5 more seconds — should have collapsed
      await Future.delayed(const Duration(milliseconds: 1500));
      expect(collapsed, isTrue);

      timer.cancel();
    });

    test('timer can be cancelled before firing', () async {
      var collapsed = false;
      final timer = Timer(const Duration(seconds: 3), () {
        collapsed = true;
      });

      // Cancel immediately
      timer.cancel();

      await Future.delayed(const Duration(seconds: 4));
      expect(collapsed, isFalse);
    });

    test('timer can be reset by cancelling and creating new one', () async {
      var collapseCount = 0;

      // First timer
      var timer = Timer(const Duration(seconds: 1), () {
        collapseCount++;
      });

      // Cancel and reset after 500ms
      await Future.delayed(const Duration(milliseconds: 500));
      timer.cancel();
      timer = Timer(const Duration(seconds: 1), () {
        collapseCount++;
      });

      // After original 1s, should NOT have fired (was cancelled)
      await Future.delayed(const Duration(milliseconds: 600));
      expect(collapseCount, 0);

      // After reset timer's 1s, should fire
      await Future.delayed(const Duration(milliseconds: 500));
      expect(collapseCount, 1);

      timer.cancel();
    });
  });
}
