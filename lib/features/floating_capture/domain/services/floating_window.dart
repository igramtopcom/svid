import '../../../downloads/domain/entities/video_preview.dart';
import '../entities/floating_window_event.dart';
import '../entities/popup_action_result.dart';

/// Floating capture window service — abstracts the multi-window plugin so
/// callers (e.g. CaptureService in Phase 1A.5) work against a stable
/// interface and unit tests can swap in [MockFloatingWindow].
///
/// Implementations:
/// - `DesktopMultiWindowFloatingWindow` — production wrapper around
///   `desktop_multi_window` plugin (spawns separate Flutter engine).
/// - `MockFloatingWindow` — in-memory test impl (records method calls,
///   exposes an inbound stream caller can drive to simulate user actions).
///
/// IPC contract (mirrors spec §3.3):
/// - Outbound (this side → popup): [showPreview], [pushQueue],
///   [clearQueue], [setQuotaState].
/// - Inbound (popup → this side): emitted on [events] stream as
///   [FloatingWindowEvent] subclasses.
abstract class FloatingWindow {
  /// Stream of events from the popup. Broadcast — multiple subscribers
  /// allowed (e.g. CaptureService + analytics + tests).
  Stream<FloatingWindowEvent> get events;

  /// Whether the popup window has been spawned (engine alive).
  /// Independent of [isVisible] — a spawned window may be hidden.
  bool get isSpawned;

  /// Whether the popup is currently visible to the user.
  bool get isVisible;

  /// Spawn the popup engine. Must be called before any other outbound
  /// method. Idempotent — second call is a no-op while still spawned.
  ///
  /// [initialPreview] is forwarded as the engine's launch arguments; the
  /// popup's main() reads them to bootstrap the first state.
  Future<void> spawn({required VideoPreview initialPreview});

  /// Show the popup if hidden. No-op if already visible. Throws
  /// [StateError] if not yet spawned.
  Future<void> show();

  /// Hide the popup but keep the engine alive (cheap re-show later).
  /// No-op if not spawned or already hidden.
  Future<void> hide();

  /// Push an additional preview onto the popup's queue (multiple URLs
  /// captured in quick succession — spec Q3 "queue in 1 popup").
  Future<void> pushQueue(VideoPreview preview);

  /// Replace the popup's primary preview with [preview]. Distinct from
  /// [pushQueue] — used when the user copies a brand-new URL after
  /// dismissing the previous popup, not when stacking.
  Future<void> showPreview(VideoPreview preview);

  /// Clear the popup's queue and hide it. Engine stays alive for
  /// fast next-time spawn. Use [dispose] to fully tear down.
  Future<void> clearQueue();

  /// Forward updated quota state to the popup so it can show the
  /// "premium upgrade" hint (spec Q9) when [remaining] hits 0.
  /// [remaining] = -1 means unlimited (premium user).
  Future<void> setQuotaState({required int remaining});

  /// v2.2 Phase 2C: tell the popup the result of the user's last terminal
  /// action (Tải ngay click → Started/Completed/Failed/AuthRequired).
  /// Popup transitions to the corresponding visual state per Stitch design.
  ///
  /// Implementations should NOT throw if the popup engine doesn't yet
  /// have a handler — main+popup ship as one bundle but a release window
  /// could leave a stale handler-less popup running. Catch + log instead.
  Future<void> setActionResult(PopupActionResult result);

  /// Tear down the popup engine + close [events]. Unrecoverable — must
  /// construct a new instance to capture again. Idempotent.
  Future<void> dispose();
}
