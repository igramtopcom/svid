import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/datasources/shared_preferences_capture_preferences_store.dart';
import '../../domain/entities/capture_preferences.dart';
import '../../domain/services/capture_preferences_store.dart';

/// Production [CapturePreferencesStore] — wraps the existing app-wide
/// SharedPreferences instance (NOT a separate file) so prefs land alongside
/// the other settings.
final capturePreferencesStoreProvider =
    Provider<CapturePreferencesStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPreferencesCapturePreferencesStore(prefs);
});

/// State container for the floating capture toggle. Loads from the store
/// once on construction; UI listens for state changes via Riverpod.
///
/// Defaults to [CapturePreferences.defaults] until the load completes —
/// avoids a UI flicker between "off" and the actual value on slow disks.
/// First-run users see "enabled=true" immediately because that's also
/// the default; persisted preferences arrive seamlessly.
class CapturePreferencesNotifier extends StateNotifier<CapturePreferences> {
  final CapturePreferencesStore _store;
  bool _loaded = false;

  CapturePreferencesNotifier(this._store) : super(CapturePreferences.defaults) {
    _load();
  }

  /// Whether [_load] has completed (first read succeeded). Tests use this
  /// to wait for initial state before asserting; production UI rarely
  /// cares because the default state is the first-run reality.
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final loaded = await _store.read();
      // Avoid clobbering a setEnabled() call that raced ahead of load.
      if (!_loaded) {
        state = loaded;
      }
    } catch (e, s) {
      appLogger.warning(
        '[CapturePrefs] initial load failed, keeping defaults',
        e,
        s,
      );
    } finally {
      _loaded = true;
    }
  }

  /// Update the enabled flag + persist. Throws nothing — write failures
  /// are logged so the toggle state still reflects the user's intent
  /// even if the disk write fails (next launch resets to last-good).
  Future<void> setEnabled(bool enabled) async {
    // Defensive against the user-toggles-during-container-dispose race:
    // the StateNotifier `state =` setter throws if `mounted` is false,
    // and that throw would propagate up to a UI handler that doesn't
    // expect it. Drop the call silently instead — the container is
    // tearing down, the UI will go away momentarily.
    if (!mounted) return;

    // Mark as loaded so a still-pending [_load] doesn't clobber the user's
    // explicit choice when it resumes from `await _store.read()`. Without
    // this, a fast user tap during the SharedPreferences read window can
    // be silently overwritten by the persisted value.
    _loaded = true;
    final updated = state.copyWith(enabled: enabled);
    state = updated;
    try {
      await _store.write(updated);
    } catch (e, s) {
      appLogger.error('[CapturePrefs] persist failed', e, s);
    }
  }
}

final capturePreferencesNotifierProvider =
    StateNotifierProvider<CapturePreferencesNotifier, CapturePreferences>(
  (ref) {
    final store = ref.watch(capturePreferencesStoreProvider);
    return CapturePreferencesNotifier(store);
  },
);
