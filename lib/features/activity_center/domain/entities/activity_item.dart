import '../../../downloads/domain/entities/download_entity.dart';
import '../../../../core/services/notification_center_service.dart';

/// Unified activity item — wraps either a download or a system notification.
sealed class ActivityItem {
  DateTime get timestamp;
  String get id;

  const ActivityItem();

  factory ActivityItem.download(DownloadEntity download) = DownloadActivityItem;
  factory ActivityItem.system(AppNotification notification) = SystemActivityItem;
}

/// Activity item backed by a download record from Drift.
class DownloadActivityItem extends ActivityItem {
  final DownloadEntity download;

  const DownloadActivityItem(this.download);

  @override
  DateTime get timestamp => download.updatedAt;

  @override
  String get id => 'dl_${download.id}';
}

/// Activity item backed by a system notification (binary updates, license, etc.).
class SystemActivityItem extends ActivityItem {
  final AppNotification notification;

  const SystemActivityItem(this.notification);

  @override
  DateTime get timestamp => notification.timestamp;

  @override
  String get id => 'sys_${notification.id}';
}
