import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import '../network/backend_dtos.dart';
import 'backend_service.dart';
import 'notification_center_service.dart';

/// Periodically polls open tickets for new admin replies and fires
/// notifications via [NotificationCenterService].
///
/// Stores the last-checked message count per ticket to detect new messages.
/// Poll interval: 5 minutes (non-blocking, fire-and-forget).
class TicketPollService {
  final BackendService _backend;
  final NotificationCenterService _notifications;
  final SharedPreferences _prefs;
  Timer? _timer;

  static const _pollInterval = Duration(minutes: 5);
  static const _storageKey = 'ticket_poll_last_counts';

  TicketPollService(this._backend, this._notifications, this._prefs);

  /// Start the polling loop.
  void start() {
    _timer?.cancel();
    // Initial check after 30s (let app settle first)
    _timer = Timer(const Duration(seconds: 30), () {
      _poll();
      // Then periodic
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    });
  }

  /// Stop polling.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final result = await _backend.listTickets();
      result.when(
        success: (tickets) {
          _checkForNewReplies(tickets);
        },
        failure: (_) {
          // Silent — don't spam logs for polling failures
        },
      );
    } catch (_) {
      // Never let polling break the app
    }
  }

  void _checkForNewReplies(List<TicketListResponse> tickets) {
    // Load stored hashes: { ticketId: updatedAtHash }
    final storedJson = _prefs.getString(_storageKey);
    final storedHashes = <String, int>{};
    if (storedJson != null) {
      try {
        final entries = storedJson.split(';');
        for (final entry in entries) {
          final parts = entry.split(':');
          if (parts.length == 2) {
            storedHashes[parts[0]] = int.tryParse(parts[1]) ?? 0;
          }
        }
      } catch (_) {}
    }

    final updatedHashes = <String, int>{};
    var hasNewReplies = false;

    for (final ticket in tickets) {
      // Only track open/in_progress/waiting_for_customer tickets
      if (ticket.status == 'resolved' || ticket.status == 'closed') {
        continue;
      }

      // Use ticket updatedAt as change indicator
      final currentHash = ticket.updatedAt.hashCode;
      updatedHashes[ticket.id] = currentHash;

      final prevHash = storedHashes[ticket.id];
      if (prevHash != null && prevHash != currentHash) {
        // Ticket was updated since last check — likely admin reply
        if (ticket.status == 'waiting_for_customer' ||
            ticket.status == 'in_progress') {
          _notifications.add(
            AppNotificationType.ticketReply,
            'New reply on: ${ticket.subject}',
            'Your support ticket has a new response. Tap to view.',
            metadata: {'ticketId': ticket.id},
          );
          hasNewReplies = true;
        }
      }
    }

    // Persist updated hashes
    final serialized =
        updatedHashes.entries.map((e) => '${e.key}:${e.value}').join(';');
    _prefs.setString(_storageKey, serialized);

    if (hasNewReplies) {
      appLogger.debug('TicketPoll: detected new admin replies');
    }
  }
}
