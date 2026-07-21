import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/startup_profiler.dart';

void main() {
  group('StartupProfiler', () {
    test('records cumulative and delta timings in order', () {
      final logs = <String>[];
      final profiler = StartupProfiler(
        logSink: logs.add,
        stopwatch: Stopwatch(),
      );

      profiler.reset(session: 'cold_start');
      profiler.mark('binding_ready');
      profiler.mark('run_app_dispatched');

      expect(profiler.marks, hasLength(2));
      expect(profiler.marks[0].label, 'binding_ready');
      expect(profiler.marks[0].deltaMs, 0);
      expect(profiler.marks[0].totalMs, 0);
      expect(profiler.marks[1].label, 'run_app_dispatched');
      expect(profiler.marks[1].deltaMs, 0);
      expect(profiler.marks[1].totalMs, 0);
      expect(logs, hasLength(2));
      expect(logs.first, contains('binding_ready'));
      expect(logs.last, contains('run_app_dispatched'));
    });

    test('buildSummary includes session label and cumulative marks', () {
      final profiler = StartupProfiler(logSink: (_) {}, stopwatch: Stopwatch());

      profiler.reset(session: 'cold_start');
      profiler.mark('binding_ready');
      profiler.mark('first_frame_presented');

      final summary = profiler.buildSummary(label: 'first_frame');

      expect(summary, contains('cold_start'));
      expect(summary, contains('first_frame'));
      expect(summary, contains('binding_ready 0ms'));
      expect(summary, contains('first_frame_presented 0ms'));
    });

    test('reset clears previous marks and starts a new session timeline', () {
      final profiler = StartupProfiler(logSink: (_) {}, stopwatch: Stopwatch());

      profiler.reset(session: 'first_run');
      profiler.mark('binding_ready');

      profiler.reset(session: 'second_run');
      profiler.mark('binding_ready');

      expect(profiler.marks, hasLength(1));
      expect(profiler.buildSummary(label: 'summary'), contains('second_run'));
      expect(
        profiler.buildSummary(label: 'summary'),
        isNot(contains('first_run')),
      );
    });
  });
}
