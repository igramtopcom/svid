import 'dart:collection';

/// Bounded LRU cache backed by [LinkedHashMap].
///
/// Reads promote the entry to most-recent. Writes evict the oldest when
/// capacity is exceeded. Used by `DefaultCaptureService._previewCache` to
/// bound memory in long-running sessions (Codex P2 audit fix).
class LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  LruCache(this.capacity) : assert(capacity > 0, 'capacity must be positive');

  /// Returns `null` if missing. On hit, the entry becomes most-recent.
  V? operator [](K key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  /// Stores [value] at [key], evicting oldest entry if at capacity.
  void operator []=(K key, V value) {
    _map.remove(key);
    if (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  void remove(K key) => _map.remove(key);

  void clear() => _map.clear();

  int get length => _map.length;

  bool containsKey(K key) => _map.containsKey(key);
}
