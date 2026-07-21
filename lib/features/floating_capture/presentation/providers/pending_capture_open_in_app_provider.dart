import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the most recently emitted "Open in SSvid" URL from the floating
/// capture popup. The user clicks this button on a non-video URL
/// (playlist / channel / search) — per spec Q18 — when they want to
/// interact with the URL in the main app rather than start a direct
/// download.
///
/// Producer (main.dart override of `captureSideEffectRouterProvider`)
/// pushes the URL string here. Consumer (HomeScreen state) listens via
/// `ref.listenManual` (with `fireImmediately: true` to avoid the lost-
/// request race covered in the 1B.1 audit) and routes the URL into the
/// home URL input field WITHOUT auto-starting a download — the user has
/// explicitly chosen the "interact, don't download yet" intent.
///
/// State `null` means "no pending request" — the seeded initial value.
final pendingCaptureOpenInAppProvider =
    StateProvider<String?>((ref) => null);
