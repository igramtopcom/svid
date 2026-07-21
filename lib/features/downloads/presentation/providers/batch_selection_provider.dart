import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the set of currently-selected download IDs for batch operations.
///
/// Non-empty == selection mode is active.
/// Clear the set to exit selection mode.
final batchSelectionProvider = StateProvider<Set<int>>((ref) => const {});

/// Tracks the index of the keyboard-focused download item in the list.
/// null = no item focused via keyboard.
final focusedDownloadIndexProvider = StateProvider<int?>((ref) => null);
