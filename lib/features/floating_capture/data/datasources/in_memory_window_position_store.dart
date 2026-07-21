import '../../domain/entities/window_position.dart';
import '../../domain/services/window_position_store.dart';

/// In-memory [WindowPositionStore] for tests.
class InMemoryWindowPositionStore implements WindowPositionStore {
  WindowPosition? _current;
  final List<WindowPosition> writes = [];
  int readCount = 0;

  InMemoryWindowPositionStore({WindowPosition? initial}) : _current = initial;

  @override
  Future<WindowPosition?> read() async {
    readCount++;
    return _current;
  }

  @override
  Future<void> write(WindowPosition position) async {
    _current = position;
    writes.add(position);
  }
}
