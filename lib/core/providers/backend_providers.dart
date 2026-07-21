import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../network/backend_client.dart';
import '../network/backend_dtos.dart';
import '../services/analytics_service.dart';
import '../services/backend_service.dart';
import '../services/device_auth_service.dart';
import '../services/error_reporter_service.dart';
import '../services/network_monitor_service.dart';
import '../services/secure_credential_store.dart';

/// Secure credential store provider (singleton)
final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SecureCredentialStore(
    prefs,
    errorReporter: ref.read(errorReporterServiceProvider),
  );
});

/// Backend API client provider (singleton).
///
/// Item B: injects ErrorReporterService and NetworkMonitorService at the
/// provider boundary so the HTTP interceptor in BackendClient gets
/// instrumentation for free. BackendService constructor stays unchanged.
final backendClientProvider = Provider<BackendClient>((ref) {
  final credentials = ref.watch(secureCredentialStoreProvider);
  final reporter = ref.read(errorReporterServiceProvider);
  final networkMonitor = ref.read(networkMonitorServiceProvider);
  final client = BackendClient(
    credentials,
    errorReporter: reporter,
    networkMonitor: networkMonitor,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Device auth service provider
final deviceAuthServiceProvider = Provider<DeviceAuthService>((ref) {
  final client = ref.watch(backendClientProvider);
  final credentials = ref.watch(secureCredentialStoreProvider);
  return DeviceAuthService(client, credentials);
});

/// Backend service provider (all API calls)
final backendServiceProvider = Provider<BackendService>((ref) {
  final client = ref.watch(backendClientProvider);
  return BackendService(client);
});

/// Whether device is registered with backend (async — check secure storage)
final isDeviceRegisteredProvider = FutureProvider<bool>((ref) async {
  final authService = ref.watch(deviceAuthServiceProvider);
  return await authService.isRegistered;
});

/// Device ID from backend registration (null if not registered)
final deviceIdProvider = FutureProvider<String?>((ref) async {
  final authService = ref.watch(deviceAuthServiceProvider);
  return await authService.deviceId;
});

/// App update state — set by StartupService when a new version is available
final appUpdateProvider = StateProvider<UpdateCheckResponse?>((ref) => null);

/// Analytics service provider (singleton, started by StartupService)
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final backendService = ref.watch(backendServiceProvider);
  final service = AnalyticsService(backendService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Active announcements — set by StartupService
final announcementsProvider = StateProvider<List<AnnouncementResponse>>((ref) => []);

/// Feature flags — set by StartupService
final featureFlagsProvider = StateProvider<List<FeatureFlagResponse>>((ref) => []);

/// Remote config — set by StartupService
final remoteConfigProvider = StateProvider<List<RemoteConfigResponse>>((ref) => []);
