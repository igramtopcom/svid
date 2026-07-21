import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

typedef StartupProfilerLogSink = void Function(String message);

class StartupMark {
  final String label;
  final int totalMs;
  final int deltaMs;

  const StartupMark({
    required this.label,
    required this.totalMs,
    required this.deltaMs,
  });
}

/// Lightweight startup profiler for real-world boot timing.
///
/// Uses a single [Stopwatch] plus structured log lines so startup timing can
/// be inspected from normal app logs without adding a profiling framework.
class StartupProfiler {
  StartupProfiler({StartupProfilerLogSink? logSink, Stopwatch? stopwatch})
    : _logSink = logSink ?? _defaultLogSink,
      _stopwatch = stopwatch ?? Stopwatch();

  static final StartupProfiler instance = StartupProfiler();

  final StartupProfilerLogSink _logSink;
  final Stopwatch _stopwatch;
  final List<StartupMark> _marks = [];
  String _session = 'startup';

  UnmodifiableListView<StartupMark> get marks => UnmodifiableListView(_marks);

  void reset({String session = 'startup'}) {
    _session = session;
    _marks.clear();
    _stopwatch
      ..reset()
      ..start();
  }

  void mark(String label) {
    if (!_stopwatch.isRunning) {
      reset(session: _session);
    }

    final totalMs = _stopwatch.elapsedMilliseconds;
    final deltaMs = totalMs - (_marks.isEmpty ? 0 : _marks.last.totalMs);
    final mark = StartupMark(label: label, totalMs: totalMs, deltaMs: deltaMs);
    _marks.add(mark);
    _logSink(_formatMark(mark));
  }

  String buildSummary({String label = 'summary'}) {
    if (_marks.isEmpty) {
      return '⏱️ [Startup] $_session $label: no marks recorded';
    }

    final timeline = _marks
        .map((mark) => '${mark.label} ${mark.totalMs}ms')
        .join(' | ');
    return '⏱️ [Startup] $_session $label: $timeline';
  }

  void logSummary({String label = 'summary'}) {
    if (_marks.isEmpty) return;
    _logSink(buildSummary(label: label));
  }

  String _formatMark(StartupMark mark) {
    return '⏱️ [Startup] $_session ${mark.label}: '
        '+${mark.deltaMs}ms (${mark.totalMs}ms total)';
  }

  static void _defaultLogSink(String message) {
    // Release logs persist warning+ only, so perf markers are elevated there
    // to ensure the timings survive in production log files.
    if (kReleaseMode) {
      appLogger.warning(message);
    } else {
      appLogger.info(message);
    }
  }
}
