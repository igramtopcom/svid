import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/ad_block_service.dart';
import '../../domain/services/fingerprint_protection_service.dart';
import '../../domain/services/https_enforcement_service.dart';
import '../../domain/services/phishing_detection_service.dart';
import '../../domain/services/popup_blocker_service.dart';
import '../../domain/services/search_engine_service.dart';

// ==================== KEYS ====================

const _adBlockEnabledKey = 'browser_ad_block_enabled';
const _popupBlockEnabledKey = 'browser_popup_block_enabled';
const _phishingDetectionEnabledKey = 'browser_phishing_detection_enabled';
const _httpsEnforcementEnabledKey = 'browser_https_enforcement_enabled';
const _fingerprintProtectionEnabledKey =
    'browser_fingerprint_protection_enabled';
const _mediaSniffingEnabledKey = 'browser_media_sniffing_enabled';

// ==================== SERVICES ====================

/// Singleton ad block service.
final adBlockServiceProvider = Provider<AdBlockService>((ref) {
  return AdBlockService();
});

/// Singleton popup blocker service.
final popupBlockerServiceProvider = Provider<PopupBlockerService>((ref) {
  return PopupBlockerService();
});

/// Singleton phishing detection service.
final phishingDetectionServiceProvider =
    Provider<PhishingDetectionService>((ref) {
  return PhishingDetectionService();
});

/// Singleton HTTPS enforcement service.
final httpsEnforcementServiceProvider =
    Provider<HttpsEnforcementService>((ref) {
  return HttpsEnforcementService();
});

/// Singleton fingerprint protection service.
final fingerprintProtectionServiceProvider =
    Provider<FingerprintProtectionService>((ref) {
  return FingerprintProtectionService();
});

// ==================== STATE ====================

/// Whether ad blocking is enabled. Default: true.
final adBlockEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_adBlockEnabledKey, defaultValue: true);
});

/// Whether popup blocking is enabled. Default: true.
final popupBlockEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_popupBlockEnabledKey, defaultValue: true);
});

/// Whether phishing detection is enabled. Default: true.
final phishingDetectionEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_phishingDetectionEnabledKey, defaultValue: true);
});

/// Whether HTTPS enforcement is enabled. Default: true.
final httpsEnforcementEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_httpsEnforcementEnabledKey, defaultValue: true);
});

/// Whether fingerprint protection is enabled. Default: true.
final fingerprintProtectionEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_fingerprintProtectionEnabledKey,
      defaultValue: true);
});

/// Whether IDM-style media sniffing is enabled. Default: false.
/// When enabled, the browser injects JS interceptors to detect media
/// network requests (video, audio, HLS/DASH streams).
final mediaSniffingEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier(_mediaSniffingEnabledKey, defaultValue: false);
});

// ==================== SEARCH ENGINE & HOME PAGE ====================

/// Selected search engine — reactive state mirroring service.
final selectedSearchEngineProvider =
    StateNotifierProvider<_SearchEngineNotifier, SearchEngine>((ref) {
  return _SearchEngineNotifier();
});

/// Home page URL — reactive state mirroring service.
final browserHomePageProvider =
    StateNotifierProvider<_HomePageNotifier, String>((ref) {
  return _HomePageNotifier();
});

class _SearchEngineNotifier extends StateNotifier<SearchEngine> {
  _SearchEngineNotifier() : super(SearchEngine.google) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('browser_search_engine');
    if (name != null) {
      state = SearchEngine.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SearchEngine.google,
      );
    }
  }

  Future<void> setEngine(SearchEngine engine) async {
    state = engine;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browser_search_engine', engine.name);
  }
}

class _HomePageNotifier extends StateNotifier<String> {
  _HomePageNotifier() : super(SearchEngineService.defaultHomePage) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('browser_home_page');
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> setHomePage(String url) async {
    final trimmed = url.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      state = SearchEngineService.defaultHomePage;
      await prefs.remove('browser_home_page');
    } else {
      state = trimmed;
      await prefs.setString('browser_home_page', trimmed);
    }
  }
}

/// StateNotifier backed by SharedPreferences for a boolean toggle.
class _BoolPrefNotifier extends StateNotifier<bool> {
  _BoolPrefNotifier(this._key, {required bool defaultValue})
      : super(defaultValue) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_key);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }

  Future<void> setValue(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}
