import '../entities/capture_download_request.dart';
import '../entities/snooze_duration.dart';
import '../entities/snooze_state.dart';

/// Side effects the main app handles in response to user actions on the
/// floating capture popup. CaptureService translates raw popup events into
/// these domain-level intents so the host (Riverpod, navigation, download
/// system) can subscribe at one place.
sealed class CaptureSideEffect {
  const CaptureSideEffect();
}

/// User clicked Download — main app kicks off the download pipeline.
final class StartDownloadRequested extends CaptureSideEffect {
  final CaptureDownloadRequest request;
  const StartDownloadRequested(this.request);
}

/// User clicked the thumbnail — main app opens the URL in the system
/// browser (per spec Q24).
final class OpenExternalUrl extends CaptureSideEffect {
  final String url;
  const OpenExternalUrl(this.url);
}

/// User clicked "Open in Svid" for a non-video URL — main app opens its
/// in-app browser/sheet (per spec Q18).
final class OpenInAppUrl extends CaptureSideEffect {
  final String url;
  const OpenInAppUrl(this.url);
}

/// User chose "Open Svid app" from the menu — main app brings its window
/// to front (per spec Q14).
final class OpenMainAppWindow extends CaptureSideEffect {
  const OpenMainAppWindow();
}

/// User chose "Settings" from the menu — main app navigates to Capture
/// settings page (per spec Q14).
final class OpenCaptureSettings extends CaptureSideEffect {
  const OpenCaptureSettings();
}

/// v2.2 Phase 2C — user just snoozed with "Until I resume" duration.
/// Main app shows a system notification breadcrumb so the user can find
/// the resume control even after the popup auto-hides. Without this,
/// untilManuallyResumed feels like the feature broke.
final class ShowSnoozeToast extends CaptureSideEffect {
  const ShowSnoozeToast();
}

/// v2.2 Phase 2D.1 (CPO feedback): popup _CompletedRow "Mở thư mục" CTA
/// — main app reveals the saved file in Finder/Explorer.
final class OpenSavedFolder extends CaptureSideEffect {
  final String path;
  const OpenSavedFolder(this.path);
}

/// v2.2 Phase 2D.1: popup _CompletedRow "Phát" CTA — main app opens the
/// matching saved download in the in-app player surface.
final class PlaySavedFile extends CaptureSideEffect {
  final String path;
  const PlaySavedFile(this.path);
}

/// Phase 2D.2 (anh Quân Windows feedback): URL was dropped by an
/// anti-spam layer (RecentUrlTracker / postActionBlocklist) so the
/// popup did NOT spawn. Previously this was silently logged and the
/// user got no feedback — they thought the feature was broken when
/// they re-copied an already-handled URL.
///
/// Main app receives this and shows a brief unobtrusive system
/// notification or in-app toast pointing the user back at the
/// downloads list. Emit is throttled at the service so the user
/// can't be spammed by repeated clipboard events on the same URL.
final class NotifyUrlDeduplicated extends CaptureSideEffect {
  final String url;
  const NotifyUrlDeduplicated(this.url);
}

/// Orchestrates the full floating capture flow: clipboard URL detection →
/// preview fetch → popup spawn/update → user action handling.
///
/// Implementations:
/// - `DefaultCaptureService` — production wiring of ClipboardMonitor +
///   FloatingWindow + LightweightPreview + SnoozeStore + QuotaPolicy.
/// - Tests use the production class with mock dependencies.
abstract class CaptureService {
  /// All side effects the main app needs to react to. Single broadcast
  /// stream — host subscribes once and pattern-matches the variants.
  Stream<CaptureSideEffect> get sideEffects;

  /// Whether [start] has been called and not yet [stop]ped/disposed.
  bool get isActive;

  /// Current snooze state. Updated whenever [snoozeFor] /
  /// [resumeFromSnooze] is called or persisted state is loaded on [start].
  SnoozeState get currentSnooze;

  /// Broadcast stream that fires whenever [currentSnooze] changes
  /// (initial load on [start], [snoozeFor], [resumeFromSnooze], or popup
  /// SnoozeSelected events). UI consumers (e.g., the Settings card) watch
  /// this so the snooze status stays in sync without manual refresh.
  Stream<SnoozeState> get snoozeChanges;

  /// Begin listening to the clipboard. Idempotent — second call no-op
  /// while still active. Loads persisted snooze state from
  /// [SnoozeStore].
  Future<void> start();

  /// Stop listening + hide the popup. Snooze state is preserved (stop is
  /// not the same as resumeFromSnooze).
  Future<void> stop();

  /// User selected a snooze duration on the popup (or via settings).
  /// Persists the new state and hides any visible popup.
  Future<void> snoozeFor(SnoozeDuration duration);

  /// Cancel any active snooze (manual or timed) and resume capture.
  Future<void> resumeFromSnooze();

  /// v2.2 safety valve: reset all anti-spam trackers (RecentUrlTracker
  /// Layer 1 + post-action blocklist Layer 4). Wired to Settings "Reset
  /// cooldowns" button so user can recover when popup appears not to
  /// trigger for a legitimate URL.
  void resetCooldowns();

  /// Tear down. Closes [sideEffects], cancels subscriptions, disposes
  /// the underlying FloatingWindow. Idempotent.
  Future<void> dispose();
}
