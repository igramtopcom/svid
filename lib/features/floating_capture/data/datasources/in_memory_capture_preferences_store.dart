import '../../domain/entities/capture_preferences.dart';
import '../../domain/services/capture_preferences_store.dart';

/// In-memory [CapturePreferencesStore] for tests. Tracks call counters so
/// tests can assert "settings were persisted" without a SharedPreferences
/// dependency.
class InMemoryCapturePreferencesStore implements CapturePreferencesStore {
  CapturePreferences _current;

  /// Every state ever written, in order. Last element = current.
  final List<CapturePreferences> writes = [];
  int readCount = 0;

  InMemoryCapturePreferencesStore({CapturePreferences? initial})
      : _current = initial ?? CapturePreferences.defaults;

  @override
  Future<CapturePreferences> read() async {
    readCount++;
    return _current;
  }

  @override
  Future<void> write(CapturePreferences prefs) async {
    _current = prefs;
    writes.add(prefs);
  }
}
