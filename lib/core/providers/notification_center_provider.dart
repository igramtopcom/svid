import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../services/notification_center_service.dart';

/// Singleton provider for NotificationCenterService
final notificationCenterServiceProvider =
    Provider<NotificationCenterService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = NotificationCenterService(prefs);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream of notification list changes
final notificationsStreamProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final service = ref.watch(notificationCenterServiceProvider);
  // Emit current state immediately, then stream updates
  return Stream.value(service.notifications).asyncExpand(
    (initial) => Stream.multi((controller) {
      controller.add(initial);
      final sub = service.stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    }),
  );
});

/// Unread notification count for badge
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsStreamProvider);
  return notifications.when(
    data: (list) => list.where((n) => !n.isRead).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});
