/// Service for basic browser fingerprint protection.
///
/// Generates JavaScript that reduces common fingerprinting vectors by
/// spoofing or blocking certain browser APIs:
/// - navigator.plugins → empty array
/// - navigator.hardwareConcurrency → 4
/// - screen.colorDepth → 24
/// - navigator.getBattery() → blocked
/// - canvas.toDataURL() → slight randomization
///
/// Auth domains (Facebook, Google, TikTok, etc.) are whitelisted because
/// fingerprint spoofing triggers anti-bot detection on login/OAuth pages.
class FingerprintProtectionService {
  /// Major platform domains where fingerprint spoofing breaks auth flows.
  /// These sites use fingerprint checks for bot detection — spoofing
  /// navigator.plugins, canvas, etc. triggers CAPTCHAs or blank pages.
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

  /// Check if fingerprint protection should be applied for the given URL.
  /// Returns false for auth domains where spoofing breaks login flows.
  static bool shouldProtect(String? url) {
    if (url == null || url.isEmpty) return true;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return true;

    final host = uri.host.toLowerCase();
    for (final domain in _authDomains) {
      if (host == domain || host.endsWith('.$domain')) {
        return false;
      }
    }
    return true;
  }

  /// Generate JavaScript to reduce fingerprinting.
  ///
  /// Returns a self-executing script (same pattern as AdBlockService).
  String generateProtectionScript() {
    return '''
(function() {
  try {
    // 1. Spoof navigator.plugins (empty PluginArray)
    Object.defineProperty(navigator, 'plugins', {
      get: function() { return []; },
      configurable: true
    });

    // 2. Spoof navigator.hardwareConcurrency to generic value
    Object.defineProperty(navigator, 'hardwareConcurrency', {
      get: function() { return 4; },
      configurable: true
    });

    // 3. Spoof screen.colorDepth to common value
    Object.defineProperty(screen, 'colorDepth', {
      get: function() { return 24; },
      configurable: true
    });

    // 4. Block navigator.getBattery()
    if (navigator.getBattery) {
      navigator.getBattery = function() {
        return Promise.reject(new Error('Battery API not available'));
      };
    }

    // 5. Randomize canvas fingerprint slightly
    var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function(type) {
      var ctx = this.getContext('2d');
      if (ctx) {
        var imgData = ctx.getImageData(0, 0, Math.min(this.width, 1), Math.min(this.height, 1));
        if (imgData.data.length > 0) {
          imgData.data[0] = imgData.data[0] ^ (Date.now() & 1);
          ctx.putImageData(imgData, 0, 0);
        }
      }
      return origToDataURL.apply(this, arguments);
    };
  } catch(e) {}
})();
''';
  }
}
