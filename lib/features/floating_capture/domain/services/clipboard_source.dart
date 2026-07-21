/// Abstract source of clipboard text changes.
///
/// Concrete implementations:
/// - `NativeClipboardSource` — uses platform-specific polling (macOS
///   NSPasteboard.changeCount @ 500ms) or event listeners (Windows
///   AddClipboardFormatListener) per spec v2.1 §3.1
/// - `MockClipboardSource` — controllable for tests
///
/// Service consumers should NOT instantiate sources directly — go through
/// [ClipboardMonitorService] which adds dedup, baseline detection, and
/// URL filtering on top of raw text events.
abstract class ClipboardSource {
  /// Read current clipboard text content. Returns null if clipboard contains
  /// non-text data (image, file, etc.) or is empty.
  Future<String?> readText();

  /// Start emitting clipboard changes via [onChange].
  ///
  /// [pollInterval] applies to polling-based implementations (macOS).
  /// Event-based implementations (Windows AddClipboardFormatListener)
  /// may ignore this parameter.
  ///
  /// Idempotent — calling start() multiple times is a no-op after first.
  Future<void> start({Duration pollInterval = const Duration(milliseconds: 500)});

  /// Stop emitting events. Source is reusable — can call start() again.
  Future<void> stop();

  /// Stream of clipboard text changes. Emits whenever clipboard content
  /// transitions to a non-null, non-empty string (whitespace-only ignored).
  ///
  /// Implementation should NOT emit:
  /// - Empty strings (after trim)
  /// - Non-text clipboard content (image/file/HTML-only)
  /// - Same content repeatedly (basic dedup at source level)
  Stream<String> get onChange;
}
