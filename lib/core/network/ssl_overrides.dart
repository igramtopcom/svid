import 'dart:io';

/// Global HTTP overrides to handle SSL certificate verification failures on Windows.
///
/// Windows fresh installs / corporate environments may lack trusted CA roots for
/// GitHub CDN (CloudFront), causing `CERTIFICATE_VERIFY_FAILED` when downloading
/// binaries. This override bypasses SSL verification ONLY for known-safe hosts
/// used by the app (GitHub releases, ffmpeg CDN, etc.).
class SvidHttpOverrides extends HttpOverrides {
  /// Hosts where SSL verification bypass is allowed.
  /// These are CDNs/services the app downloads binaries from.
  /// Minimal whitelist — only hosts actually used for binary downloads.
  /// Removed google.com (unused) and svid.app (should use proper certs).
  static const _trustedHosts = [
    'github.com',
    'githubusercontent.com',
    'cloudfront.net',
    'martin-riedl.de',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = _allowTrustedHosts;
    return client;
  }

  /// Allow bad certificates only for known-safe hosts.
  static bool _allowTrustedHosts(
    X509Certificate cert,
    String host,
    int port,
  ) {
    return _trustedHosts.any(
      (trusted) => host == trusted || host.endsWith('.$trusted'),
    );
  }
}
