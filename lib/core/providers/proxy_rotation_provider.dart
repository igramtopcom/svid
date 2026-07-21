import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/proxy_rotation_service.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';

/// Provides a [ProxyRotationService] built from the current [proxyList] setting.
///
/// Automatically re-creates the service (resetting rotation state) whenever
/// the proxy list changes in settings.
final proxyRotationServiceProvider = Provider<ProxyRotationService>((ref) {
  final proxyList = ref.watch(settingsProvider.select((s) => s.proxyList));
  return ProxyRotationService(proxies: proxyList);
});

/// Returns the active proxy URL for the current download:
/// - If [proxyList] is non-empty → round-robin from [ProxyRotationService]
/// - Else if single [proxyUrl] is set → use it
/// - Else → null (no proxy)
///
/// NOTE: This is a helper used by the home screen.  The rotation service
/// is stateful, so calling [nextProxy()] here advances the index.
String? resolveActiveProxy(WidgetRef ref) {
  final settings = ref.read(settingsProvider);
  if (settings.proxyList.isNotEmpty) {
    return ref.read(proxyRotationServiceProvider).nextProxy();
  }
  return settings.proxyUrl;
}
