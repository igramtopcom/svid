/// Service for enforcing HTTPS connections in the browser.
///
/// Auto-upgrades HTTP URLs to HTTPS and identifies insecure connections.
/// Excludes localhost and private IP ranges from enforcement.
class HttpsEnforcementService {
  /// Private IP ranges and localhost that should bypass HTTPS enforcement.
  static const Set<String> _exemptHosts = {
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
    '::1',
  };

  /// Check if an HTTP URL should be upgraded to HTTPS.
  ///
  /// Returns `true` for `http://` URLs that are NOT localhost or private IPs.
  bool shouldUpgrade(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http') return false;

    return !_isExempt(uri.host);
  }

  /// Upgrade an HTTP URL to HTTPS.
  ///
  /// Returns the HTTPS version of the URL. If already HTTPS or not HTTP,
  /// returns the original URL.
  String upgradeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.scheme != 'http') return url;
    if (_isExempt(uri.host)) return url;

    return uri.replace(scheme: 'https').toString();
  }

  /// Check if a URL is using an insecure connection.
  ///
  /// Returns `true` for non-HTTPS, non-localhost URLs.
  bool isInsecure(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (_isExempt(uri.host)) return false;

    return uri.scheme == 'http';
  }

  /// Check if a host is exempt from HTTPS enforcement.
  bool _isExempt(String host) {
    final lowerHost = host.toLowerCase();
    if (_exemptHosts.contains(lowerHost)) return true;

    // Private IP ranges: 10.x.x.x, 192.168.x.x, 172.16-31.x.x
    if (_isPrivateIp(lowerHost)) return true;

    return false;
  }

  /// Check if host is a private IP address.
  bool _isPrivateIp(String host) {
    if (host.startsWith('10.')) return true;
    if (host.startsWith('192.168.')) return true;

    // 172.16.0.0 - 172.31.255.255
    if (host.startsWith('172.')) {
      final parts = host.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) return true;
      }
    }

    return false;
  }
}
