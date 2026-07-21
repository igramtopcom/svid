import '../../../../core/config/brand_config.dart';

/// Service for blocking ads via domain matching and CSS element hiding.
///
/// Uses a hybrid approach:
/// - Domain-level blocking via navigation request interception
/// - Post-load CSS/JS injection for element hiding
class AdBlockService {
  /// Known ad/tracking domains to block at navigation level.
  static const Set<String> blockedDomains = {
    // Google Ads
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'pagead2.googlesyndication.com',
    'adservice.google.com',
    // Facebook / Meta — tracking pixel only (not connect.facebook.net
    // which is required for Facebook SDK, login, and 2FA flows)
    'facebook.com/tr',
    // Amazon Ads
    'amazon-adsystem.com',
    // Common ad networks
    'adnxs.com',
    'adsrvr.org',
    'adform.net',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'criteo.com',
    'criteo.net',
    'outbrain.com',
    'taboola.com',
    'mgid.com',
    'revcontent.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    // Tracking
    'scorecardresearch.com',
    'quantserve.com',
    'chartbeat.com',
    'hotjar.com',
    'mixpanel.com',
  };

  /// CSS selectors targeting common ad containers for element hiding.
  static const List<String> _hideSelectors = [
    // Generic ad containers
    '[id*="google_ads"]',
    '[id*="ad-container"]',
    '[id*="ad_container"]',
    '[class*="ad-banner"]',
    '[class*="ad_banner"]',
    '[class*="adsbygoogle"]',
    'ins.adsbygoogle',
    // Common ad iframes
    'iframe[src*="doubleclick"]',
    'iframe[src*="googlesyndication"]',
    'iframe[src*="amazon-adsystem"]',
    // Overlay / popup ads
    '[class*="popup-ad"]',
    '[class*="interstitial"]',
    '[id*="interstitial"]',
    // Sponsored content labels
    '[class*="sponsored-content"]',
    '[data-ad]',
    '[data-ad-slot]',
  ];

  /// Check if a URL's host matches a blocked ad domain.
  ///
  /// Returns `true` if the URL should be blocked.
  bool shouldBlock(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;

    final host = uri.host.toLowerCase();

    for (final domain in blockedDomains) {
      if (host == domain || host.endsWith('.$domain')) {
        return true;
      }
    }

    return false;
  }

  /// Generate JavaScript that hides ad elements on the page.
  ///
  /// Injects a <style> tag with `display: none !important` rules
  /// plus removes ad iframes.
  String generateHideAdsScript() {
    final selectorList = _hideSelectors.join(', ');
    // Use a combination of CSS hiding + JS removal for iframes
    return '''
(function() {
  try {
    var style = document.createElement('style');
    style.id = '${BrandConfig.current.brand.name}-adblock';
    style.textContent = '$selectorList { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; }';
    if (!document.getElementById('${BrandConfig.current.brand.name}-adblock')) {
      (document.head || document.documentElement).appendChild(style);
    }
    // Remove ad iframes
    document.querySelectorAll('iframe[src*="doubleclick"], iframe[src*="googlesyndication"], iframe[src*="amazon-adsystem"]').forEach(function(el) { el.remove(); });
  } catch(e) {}
})();
''';
  }
}
