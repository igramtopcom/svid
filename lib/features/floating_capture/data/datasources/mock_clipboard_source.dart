import 'dart:async';

import '../../domain/services/clipboard_source.dart';

/// In-memory clipboard source for tests and development.
///
/// Tests inject this instead of `NativeClipboardSource` to control timing
/// and content of clipboard "changes" deterministically.
///
/// Example:
/// ```dart
/// final source = MockClipboardSource();
/// final monitor = ClipboardMonitorService(source: source);
/// await monitor.start();
/// source.simulateClipboardChange('https://youtube.com/...');  // triggers onChange
/// ```
class MockClipboardSource implements ClipboardSource {
  String? _currentContent;
  final _controller = StreamController<String>.broadcast();
  bool _started = false;

  @override
  Future<String?> readText() async => _currentContent;

  @override
  Future<void> start({Duration pollInterval = const Duration(milliseconds: 500)}) async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
  }

  @override
  Stream<String> get onChange => _controller.stream;

  /// Test helper: simulate user copying [content] to clipboard.
  ///
  /// If [content] is empty/whitespace, treated as no-op (matches real source
  /// behavior — ignore empty clipboards).
  void simulateClipboardChange(String content) {
    if (!_started) {
      throw StateError(
        'MockClipboardSource not started — call start() before simulating',
      );
    }
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _currentContent = content;
    _controller.add(content);
  }

  /// Test helper: set initial clipboard state WITHOUT emitting an event.
  ///
  /// Used to seed the clipboard before [ClipboardMonitorService.start] —
  /// simulates the case where user had content in clipboard before app
  /// launched (per spec §5.3 baseline detection).
  ///
  /// Aliased as [simulateOrSetInitial] for readability in tests.
  void setInitialContent(String content) {
    _currentContent = content;
  }

  /// Alias for [setInitialContent] — improves test readability when expressing
  /// "user had this in clipboard already before app started".
  void simulateOrSetInitial(String content) => setInitialContent(content);

  /// Dispose internal stream controller. Tests should call in tearDown.
  Future<void> dispose() async {
    await _controller.close();
  }
}
