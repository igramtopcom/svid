/// User-controlled preferences for the floating capture feature.
///
/// Currently a single toggle ([enabled]) — kept as a class so future
/// per-feature flags (e.g., capture-on-launch override, dedup window
/// size, dismissal behaviour) can extend without touching downstream
/// consumers.
///
/// Persisted via [CapturePreferencesStore]. Default reflects spec Q6
/// "capture default ON" — first-run users get the feature without an
/// explicit opt-in step.
class CapturePreferences {
  /// Whether the floating capture pipeline runs at all.
  ///
  /// When false, [CaptureService] does not subscribe to the clipboard
  /// stream and no popups appear. The user can still receive captures
  /// by re-enabling — no per-URL gating is performed.
  final bool enabled;

  const CapturePreferences({required this.enabled});

  /// First-run default — capture is ON unless the user explicitly turns
  /// it off via Settings (spec Q6).
  static const CapturePreferences defaults = CapturePreferences(enabled: true);

  CapturePreferences copyWith({bool? enabled}) {
    return CapturePreferences(enabled: enabled ?? this.enabled);
  }

  Map<String, dynamic> toJson() => {'enabled': enabled};

  /// Forward-compatible: missing or wrong-typed `enabled` field falls back
  /// to the default (true) so a downgraded build isn't paralysed by a
  /// payload it doesn't recognise.
  factory CapturePreferences.fromJson(Map<String, dynamic> json) {
    final raw = json['enabled'];
    return CapturePreferences(
      enabled: raw is bool ? raw : defaults.enabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CapturePreferences && other.enabled == enabled);

  @override
  int get hashCode => enabled.hashCode;

  @override
  String toString() => 'CapturePreferences(enabled: $enabled)';
}
