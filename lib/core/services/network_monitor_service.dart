import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';

/// Checks current network connectivity type.
/// Used by WiFi-Only Download Mode to gate downloads to WiFi connections only.
/// Also provides a stream of online/offline status for the offline banner.
class NetworkMonitorService {
  final Connectivity _connectivity;

  NetworkMonitorService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  /// Returns true if the device is currently connected via WiFi.
  Future<bool> isWifi() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (e, st) {
      appLogger.warning('Connectivity WiFi check failed: $e');
      appLogger.debug(st.toString());
      return false;
    }
  }

  /// Returns true if the device has any network connection.
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (e, st) {
      appLogger.warning('Connectivity online check failed: $e');
      appLogger.debug(st.toString());
      return false;
    }
  }

  /// Stream that emits true/false whenever connectivity changes.
  Stream<bool> get onlineStream => _connectivity.onConnectivityChanged
      .map((results) => !results.contains(ConnectivityResult.none))
      .handleError((Object error, StackTrace stackTrace) {
        appLogger.warning(
          'Connectivity change stream failed; network banner degraded: $error',
        );
        appLogger.debug(stackTrace.toString());
      });
}

final networkMonitorServiceProvider = Provider<NetworkMonitorService>((ref) {
  return NetworkMonitorService();
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(networkMonitorServiceProvider);
  return service.onlineStream;
});
