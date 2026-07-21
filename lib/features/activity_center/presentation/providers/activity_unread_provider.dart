import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/providers/notification_center_provider.dart';

const _lastVisitedKey = 'activity_center_last_visited';

/// Service to track when the user last visited the Activity Center.
/// Items newer than this timestamp are considered "unread".
class ActivityUnreadService {
  final SharedPreferences _prefs;
  DateTime _lastVisited;

  ActivityUnreadService(this._prefs)
      : _lastVisited = _loadTimestamp(_prefs);

  static DateTime _loadTimestamp(SharedPreferences prefs) {
    final stored = prefs.getString(_lastVisitedKey);
    if (stored != null) {
      return DateTime.tryParse(stored) ?? DateTime(2020);
    }
    return DateTime(2020); // first launch: everything is "new"
  }

  DateTime get lastVisited => _lastVisited;

  /// Mark current moment as the last visit
  void markVisited() {
    _lastVisited = DateTime.now();
    _prefs.setString(_lastVisitedKey, _lastVisited.toIso8601String());
  }
}

/// Provider for the unread tracking service
final activityUnreadServiceProvider = Provider<ActivityUnreadService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ActivityUnreadService(prefs);
});

/// Count of unread activity items (downloads created after last visit + unread system notifications)
final unreadActivityCountProvider = Provider<int>((ref) {
  final service = ref.watch(activityUnreadServiceProvider);
  final lastVisited = service.lastVisited;

  // Count downloads created after last visit
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final newDownloads = downloads.where(
    (d) => d.createdAt.isAfter(lastVisited),
  ).length;

  // Count unread system notifications
  final sysNotifs = ref.watch(notificationsStreamProvider);
  final newSysCount = sysNotifs.when(
    data: (list) => list.where((n) => n.timestamp.isAfter(lastVisited)).length,
    loading: () => 0,
    error: (_, __) => 0,
  );

  return newDownloads + newSysCount;
});
