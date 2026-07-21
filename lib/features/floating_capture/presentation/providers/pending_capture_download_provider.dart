import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/capture_download_request.dart';

/// Holds the most recently emitted [CaptureDownloadRequest] from the
/// floating capture popup. Cross-feature glue between the floating
/// capture's `onDownload` side effect and the host app's download flow
/// (currently HomeScreen via `ref.listenManual`).
///
/// Producer (main.dart override of `captureSideEffectRouterProvider`)
/// pushes the latest request here. Consumer (HomeScreen state) listens
/// and triggers the existing extract-and-download pipeline. The consumer
/// is responsible for clearing the slot to `null` after handling, so the
/// same URL can be re-emitted (e.g., user re-copies after dismissing
/// without downloading).
///
/// State `null` means "no pending request" — the seeded initial value.
final pendingCaptureDownloadProvider =
    StateProvider<CaptureDownloadRequest?>((ref) => null);
