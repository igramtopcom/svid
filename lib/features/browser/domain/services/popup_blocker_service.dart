import '../../../../core/config/brand_config.dart';

/// Service for blocking unwanted pop-up windows.
///
/// Blocks cross-origin popups (typically ad/spam popups)
/// while allowing same-origin popups (legitimate site functionality).
class PopupBlockerService {
  /// Check if a popup navigation should be blocked.
  ///
  /// [currentUrl] is the URL of the page that triggered the popup.
  /// [popupUrl] is the URL the popup is trying to navigate to.
  ///
  /// Returns `true` if the popup should be blocked.
  bool shouldBlockPopup(String currentUrl, String popupUrl) {
    final currentUri = Uri.tryParse(currentUrl);
    final popupUri = Uri.tryParse(popupUrl);

    if (currentUri == null || popupUri == null) return true;

    // Block non-HTTP schemes (javascript:, data:, blob: etc.)
    if (popupUri.scheme != 'http' && popupUri.scheme != 'https') {
      return true;
    }

    // Allow same-origin popups (legitimate site functionality)
    if (_isSameOrigin(currentUri, popupUri)) {
      return false;
    }

    // Allow popups to known auth/OAuth domains (login flows use cross-origin popups)
    final popupHost = popupUri.host.toLowerCase();
    for (final domain in _authDomains) {
      if (popupHost == domain || popupHost.endsWith('.$domain')) {
        return false;
      }
    }

    // Block known popup/redirect domains
    for (final domain in _knownPopupDomains) {
      if (popupHost == domain || popupHost.endsWith('.$domain')) {
        return true;
      }
    }

    // Block cross-origin popups by default
    return true;
  }

  /// Check if two URIs share the same origin (scheme + host).
  bool _isSameOrigin(Uri a, Uri b) {
    return _rootDomain(a.host) == _rootDomain(b.host);
  }

  /// Extract root domain (e.g., "www.example.com" → "example.com").
  String _rootDomain(String host) {
    final parts = host.toLowerCase().split('.');
    if (parts.length <= 2) return host.toLowerCase();
    return parts.sublist(parts.length - 2).join('.');
  }

  /// Auth/OAuth domains that legitimately need cross-origin popups.
  static const Set<String> _authDomains = {
    'facebook.com',
    'instagram.com',
    'tiktok.com',
    'google.com',
    'accounts.google.com',
    'twitter.com',
    'x.com',
    'apple.com',
    'appleid.apple.com',
    'microsoft.com',
    'login.microsoftonline.com',
    'github.com',
    'amazon.com',
    'linkedin.com',
  };

  /// Known popup/redirect ad domains.
  static const Set<String> _knownPopupDomains = {
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'juicyads.com',
    'exoclick.com',
    'trafficjunky.com',
    'clickadu.com',
    'hilltopads.com',
    'adf.ly',
    'bit.ly',
    'shorte.st',
  };

  /// Generate JavaScript that blocks window.open popups.
  ///
  /// Overrides `window.open` to prevent ad popups from opening.
  String generateBlockPopupsScript() {
    // Auth domains that must be allowed through the JS popup blocker
    final authList = _authDomains.map((d) => "'$d'").join(',');
    return '''
(function() {
  try {
    if (window.__${BrandConfig.current.brand.name}_popup_blocked) return;
    window.__${BrandConfig.current.brand.name}_popup_blocked = true;
    var _open = window.open;
    var authDomains = [$authList];
    window.open = function(url, name, features) {
      if (!url) return null;
      try {
        var a = document.createElement('a');
        a.href = url;
        var currentHost = window.location.hostname.split('.').slice(-2).join('.');
        var popupHost = a.hostname.split('.').slice(-2).join('.');
        if (currentHost === popupHost) {
          return _open.call(window, url, name, features);
        }
        for (var i = 0; i < authDomains.length; i++) {
          if (popupHost === authDomains[i] || a.hostname.endsWith('.' + authDomains[i])) {
            return _open.call(window, url, name, features);
          }
        }
      } catch(e) {}
      return null;
    };
  } catch(e) {}
})();
''';
  }
}
