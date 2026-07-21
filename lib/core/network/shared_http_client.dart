import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Process-lifetime pooled HTTP client shared by every lightweight
/// app-side request (binary version checks, update downloads, checksum
/// manifests). Using a single client keeps TCP + TLS sockets warm across
/// calls instead of rebuilding a fresh pool per request.
///
/// CRITICAL: the exposed instance ignores `close()`. Any consumer that
/// happens to be disposed (a BinaryDownloader whose cache was evicted,
/// an auto-update flow that completed) must NOT tear down the shared
/// pool. The wrapping [_NonDisposingClient] intercepts `close()` and
/// makes it a no-op; the underlying [IOClient] stays alive until the
/// process exits. The raw `IOClient` from the `http` package closes its
/// socket pool on `close()` — a stray dispose from any caller would
/// break every other service still using the singleton, which is the
/// bug the earlier `c2c09c3b` attempt at this optimisation introduced.
final class SharedHttpClient {
  SharedHttpClient._();

  /// Shared, process-lifetime HTTP client. Call `close()` on this
  /// returned client is a no-op — dispose-safe by design.
  static final http.Client instance = _create();

  static http.Client _create() {
    final ioClient = HttpClient()
      ..idleTimeout = const Duration(seconds: 20)
      ..connectionTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 8;
    return _NonDisposingClient(IOClient(ioClient));
  }
}

/// Wraps an [http.Client] and swallows `close()` so a consumer disposing
/// its reference cannot tear down the shared pool. All other Client
/// behaviour delegates through to [_inner].
class _NonDisposingClient extends http.BaseClient {
  _NonDisposingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() {
    // NO-OP. See SharedHttpClient docstring for rationale.
  }
}
