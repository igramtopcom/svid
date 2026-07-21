/// Individual cookie entry parsed from Netscape-format cookie string
class CookieEntry {
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool isSecure;
  final DateTime? expiresAt;
  final bool isSubdomain;

  const CookieEntry({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.isSecure,
    this.expiresAt,
    this.isSubdomain = false,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isExpiringSoon {
    if (expiresAt == null) return false;
    final threeDaysFromNow = DateTime.now().add(const Duration(days: 3));
    return !isExpired && expiresAt!.isBefore(threeDaysFromNow);
  }
}

/// Summary of cookie/session health for a platform
class CookieSessionSummary {
  final String platform;
  final int totalCookies;
  final int authCookieCount;
  final int expiringSoonCount;
  final bool isHealthy;
  final DateTime? earliestExpiry;

  const CookieSessionSummary({
    required this.platform,
    required this.totalCookies,
    required this.authCookieCount,
    required this.expiringSoonCount,
    required this.isHealthy,
    this.earliestExpiry,
  });
}

/// Service to parse Netscape-format cookies and assess session health.
///
/// Pure Dart, no dependencies — highly testable.
class CookieInspectorService {
  /// Known auth cookie names per platform
  static const _authCookieNames = {
    // Google/YouTube
    'SID', 'HSID', 'SSID', 'APISID', 'SAPISID', '__Secure-1PSID',
    '__Secure-3PSID', 'LOGIN_INFO',
    // Instagram/Facebook
    'sessionid', 'c_user', 'xs', 'datr', 'ds_user_id',
    // TikTok
    'sessionid_ss', 'sid_tt', 'passport_csrf_token',
    // Reddit
    'reddit_session', 'token_v2',
    // Twitter/X
    'auth_token', 'ct0', 'twid',
    // Pinterest
    '_pinterest_sess',
    // Generic
    'session', 'token', 'access_token',
  };

  /// Parse a Netscape-format cookie string into individual [CookieEntry] items.
  ///
  /// Netscape format: `domain\tinclude_subdomains\tpath\tsecure\texpiration\tname\tvalue`
  /// Lines starting with `#` or empty lines are skipped.
  List<CookieEntry> parseCookies(String netscapeCookieString) {
    final entries = <CookieEntry>[];
    final lines = netscapeCookieString.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split('\t');
      if (parts.length < 7) continue;

      final domain = parts[0];
      final isSubdomain = parts[1].toUpperCase() == 'TRUE';
      final path = parts[2];
      final isSecure = parts[3].toUpperCase() == 'TRUE';
      final expirationStr = parts[4];
      final name = parts[5];
      final value = parts.sublist(6).join('\t'); // value may contain tabs

      DateTime? expiresAt;
      final expirationInt = int.tryParse(expirationStr);
      if (expirationInt != null && expirationInt > 0) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(
          expirationInt * 1000,
          isUtc: true,
        ).toLocal();
      }

      entries.add(CookieEntry(
        name: name,
        value: value,
        domain: domain,
        path: path,
        isSecure: isSecure,
        expiresAt: expiresAt,
        isSubdomain: isSubdomain,
      ));
    }

    return entries;
  }

  /// Count cookies grouped by domain.
  Map<String, int> countByDomain(List<CookieEntry> entries) {
    final counts = <String, int>{};
    for (final entry in entries) {
      counts[entry.domain] = (counts[entry.domain] ?? 0) + 1;
    }
    return counts;
  }

  /// Find auth-relevant cookies from the list.
  List<CookieEntry> findAuthCookies(List<CookieEntry> entries) {
    return entries
        .where((e) => _authCookieNames.contains(e.name))
        .toList();
  }

  /// Check if the session appears healthy (has non-expired auth cookies).
  bool isSessionHealthy(List<CookieEntry> entries) {
    final authCookies = findAuthCookies(entries);
    if (authCookies.isEmpty) return false;
    // Healthy if at least one auth cookie is not expired
    return authCookies.any((c) => !c.isExpired);
  }

  /// Produce a summary for a platform's cookies.
  CookieSessionSummary summarize(
    String platform,
    List<CookieEntry> entries,
  ) {
    final authCookies = findAuthCookies(entries);
    final expiringSoon = entries.where((e) => e.isExpiringSoon).toList();

    DateTime? earliest;
    for (final entry in entries) {
      if (entry.expiresAt != null && !entry.isExpired) {
        if (earliest == null || entry.expiresAt!.isBefore(earliest)) {
          earliest = entry.expiresAt;
        }
      }
    }

    return CookieSessionSummary(
      platform: platform,
      totalCookies: entries.length,
      authCookieCount: authCookies.where((c) => !c.isExpired).length,
      expiringSoonCount: expiringSoon.length,
      isHealthy: isSessionHealthy(entries),
      earliestExpiry: earliest,
    );
  }
}
