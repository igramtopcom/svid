import 'dart:math';

/// Injectable health-check function type.
/// Returns true if the proxy is reachable, false otherwise.
typedef ProxyHealthChecker = Future<bool> Function(String proxyUrl);

/// Round-robin proxy rotation with optional health checking.
///
/// Usage:
///   final svc = ProxyRotationService(proxies: ['http://p1:8080', 'http://p2:8080']);
///   final proxy = svc.nextProxy();  // sync, fast path
///   final proxy = await svc.nextHealthyProxy();  // async, with health check
class ProxyRotationService {
  final List<String> _proxies;
  final ProxyHealthChecker _checker;
  final Set<String> _unhealthy = {};
  int _index = 0;

  ProxyRotationService({
    required List<String> proxies,
    ProxyHealthChecker? checker,
  })  : _proxies = List.unmodifiable(
          proxies.where((p) => p.trim().isNotEmpty).toList(),
        ),
        _checker = checker ?? _noOpChecker;

  // ---------------------------------------------------------------------------
  // Sync API (fast path — no health check, just round-robin)
  // ---------------------------------------------------------------------------

  /// Returns the next proxy via round-robin, skipping marked-unhealthy ones.
  /// Returns null if list is empty or all proxies are marked unhealthy.
  String? nextProxy() {
    if (_proxies.isEmpty) return null;
    for (var i = 0; i < _proxies.length; i++) {
      final candidate = _proxies[(_index + i) % _proxies.length];
      if (!_unhealthy.contains(candidate)) {
        _index = (_index + i + 1) % _proxies.length;
        return candidate;
      }
    }
    // All marked unhealthy — reset and return first.
    _unhealthy.clear();
    _index = 1 % _proxies.length;
    return _proxies[0];
  }

  // ---------------------------------------------------------------------------
  // Async API (with live health check)
  // ---------------------------------------------------------------------------

  /// Returns the next healthy proxy, running [_checker] on each candidate.
  /// Returns null only when [proxies] is empty.
  Future<String?> nextHealthyProxy() async {
    if (_proxies.isEmpty) return null;
    for (var i = 0; i < _proxies.length; i++) {
      final candidate = _proxies[(_index + i) % _proxies.length];
      final ok = await _checker(candidate);
      if (ok) {
        _unhealthy.remove(candidate);
        _index = (_index + i + 1) % _proxies.length;
        return candidate;
      } else {
        _unhealthy.add(candidate);
      }
    }
    // All failed health check — reset marks, return first as last resort.
    _unhealthy.clear();
    _index = 1 % _proxies.length;
    return _proxies[0];
  }

  /// Probe all proxies concurrently and mark failures as unhealthy.
  /// Safe to call at startup for a quick pre-warm.
  Future<void> checkAll() async {
    final futures = _proxies.map((proxy) async {
      final ok = await _checker(proxy);
      if (ok) {
        _unhealthy.remove(proxy);
      } else {
        _unhealthy.add(proxy);
      }
    });
    await Future.wait(futures);
    // If every single proxy failed, clear marks to avoid permanent stall.
    if (_unhealthy.length == _proxies.length) _unhealthy.clear();
  }

  // ---------------------------------------------------------------------------
  // State management
  // ---------------------------------------------------------------------------

  /// Mark a proxy as unhealthy without running a live check.
  void markUnhealthy(String proxyUrl) => _unhealthy.add(proxyUrl);

  /// Clear all unhealthy marks (retry all proxies next round).
  void resetHealth() => _unhealthy.clear();

  // ---------------------------------------------------------------------------
  // Introspection
  // ---------------------------------------------------------------------------

  /// Total number of configured proxies (including unhealthy ones).
  int get count => _proxies.length;

  /// Number of proxies not currently marked unhealthy.
  int get healthyCount => _proxies.where((p) => !_unhealthy.contains(p)).length;

  /// Whether any proxies are configured.
  bool get hasProxies => _proxies.isNotEmpty;

  /// Immutable copy of all configured proxy URLs.
  List<String> get all => List.unmodifiable(_proxies);

  /// Proxy URLs currently marked as unhealthy.
  Set<String> get unhealthySet => Set.unmodifiable(_unhealthy);

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Future<bool> _noOpChecker(String _) async => true;
}

/// Selects a random proxy from the list without maintaining rotation state.
/// Used in one-shot contexts (e.g. scheduled downloads triggered outside a session).
String? randomProxy(List<String> proxies) {
  final valid = proxies.where((p) => p.trim().isNotEmpty).toList();
  if (valid.isEmpty) return null;
  return valid[Random().nextInt(valid.length)];
}
