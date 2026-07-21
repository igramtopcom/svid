import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../config/brand_config.dart';

// Export _AppLogOutput for cleanup function access
export 'app_logger.dart' show cleanOldLogs;

/// Global logger instance for the application
final appLogger = AppLogger();

/// Clean old log files (keep last 7 days)
/// Exposed as a top-level function for easy access
Future<void> cleanOldLogs() => _AppLogOutput.cleanOldLogs();

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  late final Logger _logger;

  factory AppLogger() => _instance;

  AppLogger._internal() {
    _logger = Logger(
      filter: _AppLogFilter(),
      printer: PrettyPrinter(
        methodCount: 0, // No stack trace for regular logs
        errorMethodCount: 3, // Minimal stack trace for errors
        lineLength: 120,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.none, // Remove timestamps to reduce clutter
      ),
      output: _AppLogOutput(),
    );
  }

  /// Log a debug message
  void debug(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log an info message
  void info(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log a warning message
  void warning(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log an error message
  void error(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log a fatal error message
  void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log a trace message
  void trace(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.t(message, error: error, stackTrace: stackTrace);
  }

  /// Read the last ~200 lines from today's log file for diagnostic submission.
  /// Returns empty string if log file is unavailable.
  Future<String> getRecentLogs({int maxLines = 200}) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(directory.path, 'logs'));
      if (!await logsDir.exists()) return '';

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final brandName = BrandConfig.current.brand.name;
      final logFile = File(p.join(logsDir.path, '${brandName}_$dateStr.log'));

      if (!await logFile.exists()) return '';

      final lines = await logFile.readAsLines();
      final start = lines.length > maxLines ? lines.length - maxLines : 0;
      return lines.sublist(start).join('\n');
    } catch (_) {
      return '';
    }
  }

  /// Close the logger (optional cleanup)
  void close() {
    _logger.close();
  }
}

/// Custom log filter that enables logging in debug mode only
class _AppLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // In release mode, only log warnings and above
    if (kReleaseMode) {
      return event.level.index >= Level.warning.index;
    }
    // In debug mode, log everything
    return true;
  }
}

/// Custom log output for the application
/// Outputs to console in debug mode and to file in all modes.
///
/// File writes use the synchronous file API so a log line is on disk before
/// `output()` returns. The previous fire-and-forget async path lost the
/// last buffered events whenever the process died before the microtask ran
/// — exactly the case for a WebView2 native crash on Windows, leaving us
/// blind in production. The throughput cost is negligible: the logger
/// filter already restricts release builds to warnings+, and a 200-byte
/// append is microseconds.
class _AppLogOutput extends LogOutput {
  static _AppLogOutput? _instance;

  File? _logFile;
  Future<void>? _initFuture;

  factory _AppLogOutput() {
    _instance ??= _AppLogOutput._internal();
    return _instance!;
  }

  _AppLogOutput._internal() {
    _initFuture = _initLogFile();
  }

  /// Initialize log file (called only once)
  Future<void> _initLogFile() async {
    try {
      // Initialize intl date formatting (required for DateFormat)
      await initializeDateFormatting();

      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(directory.path, 'logs'));

      // Create logs directory if it doesn't exist
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Create log file with date
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final brandName = BrandConfig.current.brand.name;
      _logFile = File(p.join(logsDir.path, '${brandName}_$dateStr.log'));

      // Create file if it doesn't exist
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }

      // Log initialization ONCE
      if (kDebugMode) {
        // ignore: avoid_print
        print('📝 Log file: ${_logFile!.path}');
      }
    } catch (e) {
      // If file logging fails, continue with console logging only
      if (kDebugMode) {
        // ignore: avoid_print
        print('⚠️ Failed to initialize log file: $e');
      }
    }
  }

  @override
  void output(OutputEvent event) {
    // Always print to console in debug mode
    if (kDebugMode) {
      for (var line in event.lines) {
        // ignore: avoid_print
        print(line);
      }
    }

    _writeToFileSync(event);
  }

  /// Append the log event to disk synchronously so it survives a crash.
  void _writeToFileSync(OutputEvent event) {
    final file = _logFile;
    if (file == null) {
      // First write before async _initLogFile completed: fall back to a
      // best-effort async write so the line isn't dropped entirely.
      _writeToFileAsyncFallback(event);
      return;
    }

    try {
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final buffer = StringBuffer();
      for (final line in event.lines) {
        final cleanLine = line.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
        buffer.writeln('[$timestamp] $cleanLine');
      }
      file.writeAsStringSync(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to write to log file: $e');
      }
    }
  }

  /// Async fallback for log lines emitted before the log file is open.
  /// Awaits the single in-flight init future (set in the constructor) so N
  /// early log lines don't each kick off a concurrent _initLogFile() and race
  /// on directory creation / file existence checks.
  Future<void> _writeToFileAsyncFallback(OutputEvent event) async {
    await _initFuture;
    if (_logFile != null) {
      _writeToFileSync(event);
    }
  }

  /// Clean old log files (keep last 7 days)
  static Future<void> cleanOldLogs() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(directory.path, 'logs'));

      if (!await logsDir.exists()) return;

      final now = DateTime.now();
      final files = logsDir.listSync();

      for (var file in files) {
        if (file is File && file.path.endsWith('.log')) {
          final stat = await file.stat();
          final age = now.difference(stat.modified);

          // Delete files older than 7 days
          if (age.inDays > 7) {
            await file.delete();
            if (kDebugMode) {
              // ignore: avoid_print
              print('🗑️ Deleted old log file: ${file.path}');
            }
          }
        }
      }
    } catch (e) {
      // Silently fail
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to clean old logs: $e');
      }
    }
  }
}
