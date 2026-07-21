import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the saved file path emitted by the floating capture Completed
/// banner's Play action. AppScaffold consumes this and opens the in-app
/// player surface for the matching DownloadEntity.
final pendingCapturePlaySavedFileProvider = StateProvider<String?>(
  (ref) => null,
);
