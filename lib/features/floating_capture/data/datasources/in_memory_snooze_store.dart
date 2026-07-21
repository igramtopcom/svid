import '../../domain/entities/snooze_state.dart';
import '../../domain/services/snooze_store.dart';

/// In-memory [SnoozeStore] for tests. Tracks reads + writes so tests can
/// assert call ordering without a SharedPreferences dependency.
class InMemorySnoozeStore implements SnoozeStore {
  SnoozeState _current = SnoozeState.inactive;

  /// All states ever written, in order. Last element is current.
  /// Tests can use this to assert that snooze persistence happened
  /// (vs. just running in memory inside CaptureService).
  final List<SnoozeState> writes = [];

  /// Number of times [read] was called — useful to verify CaptureService
  /// reads exactly once on start (vs. polling).
  int readCount = 0;

  /// Pre-seed an initial state (simulates app restart with previously
  /// saved snooze).
  InMemorySnoozeStore({SnoozeState? initial}) {
    if (initial != null) _current = initial;
  }

  @override
  Future<SnoozeState> read() async {
    readCount++;
    return _current;
  }

  @override
  Future<void> write(SnoozeState state) async {
    _current = state;
    writes.add(state);
  }
}
