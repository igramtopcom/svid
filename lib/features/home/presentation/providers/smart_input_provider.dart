/// V2 Smart Input — Riverpod state with debounced classification
///
/// Wraps a [TextEditingController] and runs [UrlClassifierService] over
/// its value with a 500ms debounce per UI Spec §4.1. Consumers read
/// [SmartInputState] to render the adaptive CTA, the customize-icon
/// visibility matrix, and the preset dropdown enable state.
///
/// The provider is `keepAlive: false` — Home unmounts → state disposes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/url_classifier_service.dart';

/// Snapshot of smart-input state shared across V2 widgets.
@immutable
class SmartInputState {
  final String rawText;

  /// Debounced classification of [rawText]. Updated 500ms after the
  /// last keystroke / paste / programmatic set.
  final SmartInputType type;

  /// True while the debounce timer is active and a re-classification
  /// is pending. Used by [SmartCTAButton] to render the disabled
  /// "Đang phân tích..." state instead of a stale label.
  final bool isReclassifying;

  const SmartInputState({
    required this.rawText,
    required this.type,
    required this.isReclassifying,
  });

  static const empty = SmartInputState(
    rawText: '',
    type: SmartInputType.empty,
    isReclassifying: false,
  );

  SmartInputState copyWith({
    String? rawText,
    SmartInputType? type,
    bool? isReclassifying,
  }) =>
      SmartInputState(
        rawText: rawText ?? this.rawText,
        type: type ?? this.type,
        isReclassifying: isReclassifying ?? this.isReclassifying,
      );
}

/// Notifier driving [smartInputProvider]. Reads from a single
/// [TextEditingController] passed by the host widget so paste, keyboard
/// shortcuts and clipboard radar all funnel through one source-of-truth.
class SmartInputController extends StateNotifier<SmartInputState> {
  SmartInputController({
    UrlClassifierService? classifier,
    Duration? debounce,
  })  : _classifier = classifier ?? const UrlClassifierService(),
        _debounce = debounce ?? const Duration(milliseconds: 500),
        super(SmartInputState.empty);

  final UrlClassifierService _classifier;
  final Duration _debounce;
  Timer? _timer;

  /// Push a new raw value. Triggers debounced classification; the
  /// `isReclassifying` flag flips immediately so UI can disable the CTA
  /// while waiting for the timer to fire.
  void update(String raw) {
    _timer?.cancel();
    state = state.copyWith(rawText: raw, isReclassifying: true);
    _timer = Timer(_debounce, () {
      final classified = _classifier.classify(raw);
      state = state.copyWith(type: classified, isReclassifying: false);
    });
  }

  /// Clear input + cancel any pending classification.
  void clear() {
    _timer?.cancel();
    state = SmartInputState.empty;
  }

  /// Force-flush the debounce — used by submit handlers that cannot
  /// wait for the timer (Enter key, programmatic submit).
  void flush() {
    _timer?.cancel();
    final classified = _classifier.classify(state.rawText);
    state = state.copyWith(type: classified, isReclassifying: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Provider exposing the smart-input state for V2 Home.
final smartInputProvider =
    StateNotifierProvider.autoDispose<SmartInputController, SmartInputState>(
  (ref) => SmartInputController(),
);
