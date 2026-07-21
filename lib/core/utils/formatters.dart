import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

class Formatters {
  Formatters._();

  /// Format DateTime to readable string. Locale-aware via [DateFormat.yMMMd]
  /// + [DateFormat.jm] skeleton API — adapts to locale grammar (en:
  /// 'Dec 30, 2025 9:45 AM'; ja: '2025年12月30日 9:45'; de:
  /// '30. Dez. 2025, 09:45'). Driven by [Intl.getCurrentLocale] which
  /// `main.dart` mirrors to EasyLocalization's active locale via
  /// `Intl.defaultLocale` on startup + on locale-switch.
  static String formatDateTime(DateTime dateTime) {
    final loc = Intl.getCurrentLocale();
    return '${DateFormat.yMMMd(loc).format(dateTime)} '
        '${DateFormat.jm(loc).format(dateTime)}';
  }

  /// Format DateTime to date only. Locale-aware via [DateFormat.yMMMd] skeleton.
  static String formatDate(DateTime dateTime) {
    return DateFormat.yMMMd(Intl.getCurrentLocale()).format(dateTime);
  }

  /// Format DateTime to time only. Locale-aware via [DateFormat.jm] skeleton.
  static String formatTime(DateTime dateTime) {
    return DateFormat.jm(Intl.getCurrentLocale()).format(dateTime);
  }

  /// Format DateTime to relative time (e.g., "2 hours ago", "in 5 minutes").
  /// Resolves through AppLocalizations so output is locale-aware native.
  static String formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.isNegative) {
      final future = dateTime.difference(now);
      if (future.inDays > 0) {
        return AppLocalizations.formattersRelativeTimeInDays(future.inDays);
      } else if (future.inHours > 0) {
        return AppLocalizations.formattersRelativeTimeInHours(future.inHours);
      } else if (future.inMinutes > 0) {
        return AppLocalizations.formattersRelativeTimeInMinutes(
          future.inMinutes,
        );
      } else {
        return AppLocalizations.formattersRelativeTimeJustNow;
      }
    }

    if (difference.inDays > 30) {
      return formatDate(dateTime);
    } else if (difference.inDays > 0) {
      return AppLocalizations.formattersRelativeTimeDaysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return AppLocalizations.formattersRelativeTimeHoursAgo(
        difference.inHours,
      );
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.formattersRelativeTimeMinutesAgo(
        difference.inMinutes,
      );
    } else {
      return AppLocalizations.formattersRelativeTimeJustNow;
    }
  }

  /// Format Duration to readable string (e.g., "2h 30m 15s")
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Format Duration to short readable string (e.g., "2:30:15" or "5:23")
  static String formatDurationShort(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format percentage (0.0 - 1.0 to 0% - 100%)
  static String formatPercentage(double value, {int decimals = 0}) {
    final percentage = (value * 100).clamp(0, 100);
    return '${percentage.toStringAsFixed(decimals)}%';
  }

  /// Format speed (bytes per second to KB/s, MB/s, etc.)
  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(2)} KB/s';
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
    }
  }

  /// Format number with thousand separators (e.g., 1,234,567)
  static String formatNumber(num number) {
    return NumberFormat('#,###').format(number);
  }

  /// Format number as currency
  static String formatCurrency(num amount, {String symbol = '\$', int decimals = 2}) {
    return '$symbol${amount.toStringAsFixed(decimals)}';
  }

  /// Format remaining time based on current speed and remaining bytes
  static String formatRemainingTime(int remainingBytes, int bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      return 'Unknown';
    }

    final remainingSeconds = remainingBytes ~/ bytesPerSecond;
    final duration = Duration(seconds: remainingSeconds);

    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
