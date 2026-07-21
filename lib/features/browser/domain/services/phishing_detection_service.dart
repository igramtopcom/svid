/// Heuristic-based phishing detection service.
///
/// Checks URLs against multiple signals:
/// - Homograph/IDN attacks (mixed script domains)
/// - Suspicious TLDs (.xyz, .top, .loan, etc.)
/// - Lookalike domains (edit distance to known brands)
/// - Excessive subdomain depth (≥4 levels)
/// - IP-based URLs
/// - Known phishing URL patterns
enum PhishingCheckResult { safe, suspicious, dangerous }

class PhishingDetectionService {
  /// TLDs commonly associated with phishing/spam.
  static const Set<String> _suspiciousTlds = {
    '.xyz',
    '.top',
    '.club',
    '.buzz',
    '.loan',
    '.work',
    '.click',
    '.gdn',
    '.icu',
    '.rest',
    '.surf',
    '.casa',
  };

  /// Major brand domains to check for lookalikes.
  static const List<String> _brandDomains = [
    'google',
    'youtube',
    'facebook',
    'instagram',
    'paypal',
    'apple',
    'microsoft',
    'amazon',
    'netflix',
    'twitter',
    'github',
    'linkedin',
    'dropbox',
    'chase',
    'bankofamerica',
    'wellsfargo',
  ];

  /// Known phishing URL path patterns.
  static const List<String> _phishingPathPatterns = [
    'login-verify',
    'account-verify',
    'secure-update',
    'login-confirm',
    'account-confirm',
    'signin-verify',
    'password-reset-confirm',
    'security-alert',
    'suspended-account',
    'unusual-activity',
  ];

  /// Analyze a URL for phishing indicators.
  ///
  /// Returns [PhishingCheckResult.dangerous] for strong signals,
  /// [PhishingCheckResult.suspicious] for weaker signals, or
  /// [PhishingCheckResult.safe] if no signals detected.
  PhishingCheckResult checkUrl(String url) {
    // Pre-check: scan raw URL for non-ASCII characters in the host portion
    // (Uri.tryParse may fail to parse non-ASCII hostnames)
    if (_hasNonAsciiInHost(url)) {
      return PhishingCheckResult.dangerous;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return PhishingCheckResult.safe;

    // Only check HTTP/HTTPS URLs
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return PhishingCheckResult.safe;
    }

    final host = uri.host.toLowerCase();

    // Check 1: IP-based URLs (e.g., http://192.168.1.1/login)
    if (_isIpAddress(host)) {
      return PhishingCheckResult.suspicious;
    }

    // Check 2: Homograph/IDN attack — contains non-ASCII in domain
    if (_hasHomographAttack(host)) {
      return PhishingCheckResult.dangerous;
    }

    // Check 3: Lookalike domain (edit distance ≤ 2 to a known brand)
    final lookalikeResult = _checkLookalikeDomain(host);
    if (lookalikeResult == PhishingCheckResult.dangerous) {
      return PhishingCheckResult.dangerous;
    }

    // Check 4: Known phishing path patterns
    if (_hasPhishingPathPattern(uri.path)) {
      return PhishingCheckResult.suspicious;
    }

    // Check 5: Suspicious TLD
    if (_hasSuspiciousTld(host)) {
      return PhishingCheckResult.suspicious;
    }

    // Check 6: Excessive subdomain depth (≥ 4 levels)
    if (_hasExcessiveSubdomains(host)) {
      return PhishingCheckResult.suspicious;
    }

    return PhishingCheckResult.safe;
  }

  /// Returns a human-readable reason for the phishing check result.
  String? getWarningReason(String url) {
    if (_hasNonAsciiInHost(url)) {
      return 'Possible homograph attack';
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final host = uri.host.toLowerCase();

    if (_isIpAddress(host)) {
      return 'IP address URL';
    }
    if (_hasHomographAttack(host)) {
      return 'Possible homograph attack';
    }
    final brand = _findLookalikeBrand(host);
    if (brand != null) {
      return 'Looks similar to $brand';
    }
    if (_hasPhishingPathPattern(uri.path)) {
      return 'Suspicious URL pattern';
    }
    if (_hasSuspiciousTld(host)) {
      return 'Suspicious domain extension';
    }
    if (_hasExcessiveSubdomains(host)) {
      return 'Excessive subdomains';
    }
    return null;
  }

  /// Check for non-ASCII characters in the host portion of a raw URL string.
  /// This catches IDN homograph attacks even when Uri.tryParse fails.
  bool _hasNonAsciiInHost(String url) {
    // Extract host portion from raw URL: after "://" and before "/" or ":"
    final schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) return false;
    final hostStart = schemeEnd + 3;
    if (hostStart >= url.length) return false;

    var hostEnd = url.length;
    for (int i = hostStart; i < url.length; i++) {
      final c = url.codeUnitAt(i);
      if (c == 0x2F || c == 0x3A || c == 0x3F || c == 0x23) {
        // '/' or ':' or '?' or '#'
        hostEnd = i;
        break;
      }
    }

    for (int i = hostStart; i < hostEnd; i++) {
      if (url.codeUnitAt(i) > 127) return true;
    }
    return false;
  }

  /// Check if the host is an IP address (IPv4).
  bool _isIpAddress(String host) {
    return RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }

  /// Check for non-ASCII characters in domain (IDN homograph attack).
  bool _hasHomographAttack(String host) {
    // xn-- is punycode prefix for internationalized domains
    if (host.contains('xn--')) return true;
    // Check for non-ASCII characters
    for (int i = 0; i < host.length; i++) {
      if (host.codeUnitAt(i) > 127) return true;
    }
    return false;
  }

  /// Check if the domain is a lookalike of a known brand.
  PhishingCheckResult _checkLookalikeDomain(String host) {
    final brand = _findLookalikeBrand(host);
    if (brand != null) return PhishingCheckResult.dangerous;
    return PhishingCheckResult.safe;
  }

  /// Find which brand the domain looks similar to, if any.
  String? _findLookalikeBrand(String host) {
    // Extract the registrable domain (e.g., "example" from "sub.example.com")
    final parts = host.split('.');
    if (parts.length < 2) return null;

    // Check the second-level domain
    final sld = parts[parts.length - 2];

    for (final brand in _brandDomains) {
      // Skip exact match (that's the real site)
      if (sld == brand) return null;

      // Check edit distance ≤ 2
      if (_editDistance(sld, brand) <= 2 && _editDistance(sld, brand) > 0) {
        return brand;
      }
    }
    return null;
  }

  /// Check for known phishing URL path patterns.
  bool _hasPhishingPathPattern(String path) {
    final lowerPath = path.toLowerCase();
    for (final pattern in _phishingPathPatterns) {
      if (lowerPath.contains(pattern)) return true;
    }
    return false;
  }

  /// Check if the TLD is commonly used for phishing.
  bool _hasSuspiciousTld(String host) {
    for (final tld in _suspiciousTlds) {
      if (host.endsWith(tld)) return true;
    }
    return false;
  }

  /// Check if domain has excessive subdomain depth (≥ 4 levels).
  bool _hasExcessiveSubdomains(String host) {
    return host.split('.').length >= 5; // e.g., a.b.c.d.example.com = 5 parts
  }

  /// Exposed for testing.
  static int editDistanceForTest(String a, String b) => _editDistance(a, b);

  /// Compute Levenshtein edit distance between two strings.
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final la = a.length;
    final lb = b.length;

    // Use single-row optimization
    final row = List<int>.generate(lb + 1, (i) => i);

    for (int i = 1; i <= la; i++) {
      var prev = i - 1;
      row[0] = i;
      for (int j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final temp = row[j];
        row[j] = [
          row[j] + 1, // deletion
          row[j - 1] + 1, // insertion
          prev + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
        prev = temp;
      }
    }
    return row[lb];
  }
}
