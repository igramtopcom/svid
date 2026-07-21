import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Type of in-app notification
enum AppNotificationType {
  downloadComplete,
  downloadFailed,
  ytdlpUpdateCompleted,
  ytdlpUpdateFailed,
  ffmpegUpdateCompleted,
  ffmpegUpdateFailed,
  qualityFallbackApplied,
  licenseActivated,
  licenseActivationFailed,

  /// Local state said premium, backend said not. Common causes: license
  /// expired server-side, multi-device cap exceeded, license revoked.
  /// We surface a notification so the user isn't silently demoted to free
  /// without ever being told why.
  licenseDeactivated,

  /// Subscription expires within 7 days. Fires once per 24h via startup check.
  subscriptionExpiryWarning,

  /// Admin replied to a support ticket.
  ticketReply,

  /// New video detected on a subscribed YouTube channel.
  youtubeNewVideo,
}

/// In-app notification entry
class AppNotification {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  /// Optional metadata for navigation (e.g., ticketId for ticket replies).
  final Map<String, String>? metadata;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
    if (metadata != null) 'metadata': metadata,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: AppNotificationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AppNotificationType.downloadComplete,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      metadata:
          json['metadata'] != null
              ? Map<String, String>.from(json['metadata'] as Map)
              : null,
    );
  }
}

/// In-app notification center with circular buffer and persistence
class NotificationCenterService {
  static const String _storageKey = 'notification_center_data';
  static const int maxNotifications = 50;
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  List<AppNotification> _notifications = [];
  final StreamController<List<AppNotification>> _controller =
      StreamController<List<AppNotification>>.broadcast();

  NotificationCenterService(this._prefs) {
    _load();
  }

  /// Current notifications (newest first)
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// Stream of notification list changes
  Stream<List<AppNotification>> get stream => _controller.stream;

  /// Add a new notification with optional metadata for navigation context.
  void add(
    AppNotificationType type,
    String title,
    String body, {
    Map<String, String>? metadata,
  }) {
    final notification = AppNotification(
      id: _uuid.v4(),
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _notifications.insert(0, notification);

    // Circular buffer: evict oldest when exceeding max
    if (_notifications.length > maxNotifications) {
      _notifications = _notifications.sublist(0, maxNotifications);
    }

    _save();
    _controller.add(notifications);
  }

  /// Mark all notifications as read
  void markAllRead() {
    bool changed = false;
    _notifications =
        _notifications.map((n) {
          if (!n.isRead) {
            changed = true;
            return n.copyWith(isRead: true);
          }
          return n;
        }).toList();

    if (changed) {
      _save();
      _controller.add(notifications);
    }
  }

  /// Dismiss a single notification by ID
  void dismiss(String id) {
    final before = _notifications.length;
    _notifications = _notifications.where((n) => n.id != id).toList();
    if (_notifications.length != before) {
      _save();
      _controller.add(notifications);
    }
  }

  /// Clear all notifications
  void clearAll() {
    if (_notifications.isEmpty) return;
    _notifications = [];
    _save();
    _controller.add(notifications);
  }

  /// Count of unread notifications
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void _load() {
    final json = _prefs.getString(_storageKey);
    if (json == null) return;

    try {
      final list = jsonDecode(json) as List;
      _notifications =
          list
              .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
      _notifications = [];
    }
  }

  void _save() {
    final json = jsonEncode(_notifications.map((n) => n.toJson()).toList());
    _prefs.setString(_storageKey, json);
  }

  /// Dispose the stream controller
  void dispose() {
    _controller.close();
  }
}
