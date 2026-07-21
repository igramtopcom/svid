import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/services/notification_center_service.dart';

void main() {
  late NotificationCenterService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<NotificationCenterService> createService([
    Map<String, Object>? initialValues,
  ]) async {
    if (initialValues != null) {
      SharedPreferences.setMockInitialValues(initialValues);
    }
    final prefs = await SharedPreferences.getInstance();
    return NotificationCenterService(prefs);
  }

  group('NotificationCenterService', () {
    test('starts with empty notifications', () async {
      service = await createService();
      expect(service.notifications, isEmpty);
      expect(service.unreadCount, 0);
    });

    test('add() inserts notification at front', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'Download complete',
        'video.mp4',
      );

      expect(service.notifications.length, 1);
      expect(service.notifications.first.title, 'Download complete');
      expect(service.notifications.first.body, 'video.mp4');
      expect(
        service.notifications.first.type,
        AppNotificationType.downloadComplete,
      );
      expect(service.notifications.first.isRead, false);
    });

    test('add() newest notification is first', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'First',
        'first.mp4',
      );
      service.add(
        AppNotificationType.downloadFailed,
        'Second',
        'second.mp4',
      );

      expect(service.notifications.length, 2);
      expect(service.notifications[0].title, 'Second');
      expect(service.notifications[1].title, 'First');
    });

    test('circular buffer evicts oldest when exceeding max', () async {
      service = await createService();

      // Add maxNotifications + 1 items
      for (int i = 0; i < NotificationCenterService.maxNotifications + 1; i++) {
        service.add(
          AppNotificationType.downloadComplete,
          'Notification $i',
          'body $i',
        );
      }

      expect(
        service.notifications.length,
        NotificationCenterService.maxNotifications,
      );
      // The first notification (index 0) should be gone
      expect(service.notifications.last.title, 'Notification 1');
      expect(
        service.notifications.first.title,
        'Notification ${NotificationCenterService.maxNotifications}',
      );
    });

    test('markAllRead() marks all as read', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'A',
        'a.mp4',
      );
      service.add(
        AppNotificationType.downloadFailed,
        'B',
        'b.mp4',
      );

      expect(service.unreadCount, 2);

      service.markAllRead();

      expect(service.unreadCount, 0);
      expect(service.notifications.every((n) => n.isRead), true);
    });

    test('markAllRead() does nothing when all already read', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'A',
        'a.mp4',
      );
      service.markAllRead();

      // Call again - should not emit
      int emitCount = 0;
      service.stream.listen((_) => emitCount++);
      service.markAllRead();

      // Allow async processing
      await Future.delayed(Duration.zero);
      expect(emitCount, 0);
    });

    test('clearAll() removes all notifications', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'A',
        'a.mp4',
      );
      service.add(
        AppNotificationType.downloadFailed,
        'B',
        'b.mp4',
      );

      service.clearAll();

      expect(service.notifications, isEmpty);
      expect(service.unreadCount, 0);
    });

    test('clearAll() does nothing when already empty', () async {
      service = await createService();

      int emitCount = 0;
      service.stream.listen((_) => emitCount++);
      service.clearAll();

      await Future.delayed(Duration.zero);
      expect(emitCount, 0);
    });

    test('stream emits on add', () async {
      service = await createService();

      final emissions = <List<AppNotification>>[];
      service.stream.listen(emissions.add);

      service.add(
        AppNotificationType.downloadComplete,
        'Test',
        'test.mp4',
      );

      await Future.delayed(Duration.zero);
      expect(emissions.length, 1);
      expect(emissions.first.length, 1);
    });

    test('stream emits on markAllRead', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'Test',
        'test.mp4',
      );

      final emissions = <List<AppNotification>>[];
      service.stream.listen(emissions.add);

      service.markAllRead();

      await Future.delayed(Duration.zero);
      expect(emissions.length, 1);
      expect(emissions.first.first.isRead, true);
    });

    test('stream emits on clearAll', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'Test',
        'test.mp4',
      );

      final emissions = <List<AppNotification>>[];
      service.stream.listen(emissions.add);

      service.clearAll();

      await Future.delayed(Duration.zero);
      expect(emissions.length, 1);
      expect(emissions.first, isEmpty);
    });

    test('unreadCount counts only unread notifications', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'A',
        'a.mp4',
      );
      service.add(
        AppNotificationType.downloadFailed,
        'B',
        'b.mp4',
      );
      service.add(
        AppNotificationType.downloadComplete,
        'C',
        'c.mp4',
      );

      expect(service.unreadCount, 3);

      service.markAllRead();
      expect(service.unreadCount, 0);

      // Add another after marking all read
      service.add(
        AppNotificationType.downloadComplete,
        'D',
        'd.mp4',
      );
      expect(service.unreadCount, 1);
    });

    test('JSON serialization round-trip preserves data', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'Completed',
        'video.mp4',
      );
      service.add(
        AppNotificationType.downloadFailed,
        'Failed',
        'audio.mp3',
      );
      service.markAllRead();

      // Create a new service instance that loads from same SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final service2 = NotificationCenterService(prefs);

      expect(service2.notifications.length, 2);
      expect(service2.notifications[0].title, 'Failed');
      expect(service2.notifications[0].isRead, true);
      expect(
        service2.notifications[0].type,
        AppNotificationType.downloadFailed,
      );
      expect(service2.notifications[1].title, 'Completed');
      expect(service2.notifications[1].isRead, true);
      expect(
        service2.notifications[1].type,
        AppNotificationType.downloadComplete,
      );
    });

    test('loads from corrupted JSON gracefully', () async {
      service = await createService({
        'notification_center_data': 'not valid json{{{',
      });

      expect(service.notifications, isEmpty);
    });

    test('AppNotification.fromJson handles missing isRead', () {
      final json = {
        'id': 'test-id',
        'type': 'downloadComplete',
        'title': 'Test',
        'body': 'body',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final notification = AppNotification.fromJson(json);
      expect(notification.isRead, false);
    });

    test('AppNotification.toJson and fromJson round-trip', () {
      final original = AppNotification(
        id: 'abc-123',
        type: AppNotificationType.downloadFailed,
        title: 'Download failed',
        body: 'file.mp4',
        timestamp: DateTime(2026, 2, 27, 10, 30),
        isRead: true,
      );

      final json = original.toJson();
      final restored = AppNotification.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.timestamp, original.timestamp);
      expect(restored.isRead, original.isRead);
    });

    test('notifications list is unmodifiable', () async {
      service = await createService();
      service.add(
        AppNotificationType.downloadComplete,
        'Test',
        'test.mp4',
      );

      expect(
        () => service.notifications.add(AppNotification(
          id: 'x',
          type: AppNotificationType.downloadComplete,
          title: 'x',
          body: 'x',
          timestamp: DateTime.now(),
        )),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
