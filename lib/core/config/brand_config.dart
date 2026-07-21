import 'package:flutter/material.dart';

/// Brand identifier, resolved at compile time via `--dart-define=BRAND=svid`.
enum Brand {
  svid,
  vidcombo;

  static Brand fromString(String value) {
    return Brand.values.firstWhere(
      (b) => b.name == value.toLowerCase(),
      orElse: () => Brand.svid,
    );
  }
}

/// Backend protocol type — determines which adapter stack to use.
enum BackendType {
  /// Svid: Go backend with X-API-Key header, REST API
  go,

  /// VidCombo: PHP backend with query-param device_id + license_key
  php,
}

/// Brand-specific color palette.
class BrandColors {
  final Color brand;
  final Color brandLight;
  final Color brandDark;
  final Color accentHighlight;
  final Color accentMuted;

  /// Gradient primary color (start)
  final Color gradientStart;

  /// Gradient primary color (end)
  final Color gradientEnd;

  /// Extended gradient middle color
  final Color gradientMid;

  /// Extended gradient tail color
  final Color gradientTail;

  // ── Light Theme Utility Colors ──
  // Tinted to match brand warmth (Svid=warm, VidCombo=cool).

  /// Muted foreground — disabled icons, inactive tabs (light mode)
  final Color lightMuted;

  /// Muted metadata text — timestamps, secondary info (light mode)
  /// Full opacity, WCAG AA safe on white backgrounds.
  final Color lightMetaText;

  /// Base light surface — app background (light mode)
  final Color lightBase;

  /// Elevated light surface — cards, panels (light mode)
  final Color lightElevated;

  // ── Dark Theme Utility Colors ──
  // Tinted to match brand warmth (Svid=warm, VidCombo=cool).

  /// Muted foreground — disabled icons, inactive tabs, subtle borders
  final Color darkMuted;

  /// Light text on dark backgrounds — primary readable text
  final Color darkLightText;

  /// Muted metadata text — timestamps, secondary info, placeholders
  final Color darkMetaText;

  /// Base dark surface — deepest background layer
  final Color darkBase;

  /// Elevated dark surface — cards, panels, containers above base
  final Color darkElevated;

  // ── Mission Briefing tokens ──
  // Used by the operator-grade download config dialog and any other surface
  // that needs a deeper inset well or rotating accent colors.

  /// Deeper-than-base surface — inset wells for hero cards & quality rows.
  /// Visually 1-2 steps darker than darkBase. Light-mode equivalent below.
  final Color darkSurfaceLowest;

  /// Light-mode equivalent of darkSurfaceLowest — softest tinted card surface.
  final Color lightSurfaceLowest;

  /// Secondary accent — peach/cyan for "rotating" section icons (time range,
  /// format, sponsor block). Visually distinct from accentHighlight.
  final Color accentSecondary;

  /// Tertiary accent — teal/lavender for the rarest section (additional opts).
  final Color accentTertiary;

  // ── Home Dark Operator Tokens ──
  // Semantic surface ladder for the Home screen dark mode.
  // Each step is a flat opaque color — no alpha blending, no opacity stack.

  /// Root app canvas — deepest, darkest point. Below panel.
  final Color homeDarkAppBg;

  /// Card / list-item resting surface. Visually above panelBackground (= darkBase).
  final Color homeDarkCardBg;

  /// Card hover state. Immediate, no staring required.
  final Color homeDarkCardHover;

  /// Card selected state. Accent-tinted (blue/wine) — different hue from hover.
  final Color homeDarkCardSelected;

  /// Card active/downloading state. Deep accent well.
  final Color homeDarkCardActive;

  /// Hairline divider — supplementary only, never replaces surface hierarchy.
  final Color homeDarkBorderSubtle;

  /// Strong border — input outlines, section separators.
  final Color homeDarkBorderStrong;

  /// Secondary text on dark — dimmer than darkMetaText, WCAG AA on card.
  final Color homeDarkTextSecondary;

  /// Muted text — timestamps, disabled. WCAG AA on card.
  final Color homeDarkTextMuted;

  /// Input default border.
  final Color homeDarkInputBorder;

  /// Accent background well — flat tint for selected/active accent areas.
  final Color homeDarkAccentSoft;

  const BrandColors({
    required this.brand,
    required this.brandLight,
    required this.brandDark,
    required this.accentHighlight,
    required this.accentMuted,
    required this.gradientStart,
    required this.gradientEnd,
    required this.gradientMid,
    required this.gradientTail,
    required this.lightMuted,
    required this.lightMetaText,
    required this.lightBase,
    required this.lightElevated,
    required this.darkMuted,
    required this.darkLightText,
    required this.darkMetaText,
    required this.darkBase,
    required this.darkElevated,
    required this.darkSurfaceLowest,
    required this.lightSurfaceLowest,
    required this.accentSecondary,
    required this.accentTertiary,
    required this.homeDarkAppBg,
    required this.homeDarkCardBg,
    required this.homeDarkCardHover,
    required this.homeDarkCardSelected,
    required this.homeDarkCardActive,
    required this.homeDarkBorderSubtle,
    required this.homeDarkBorderStrong,
    required this.homeDarkTextSecondary,
    required this.homeDarkTextMuted,
    required this.homeDarkInputBorder,
    required this.homeDarkAccentSoft,
  });
}

/// Abstract brand configuration. Each brand implements this with its own values.
///
/// Resolved once at startup from `--dart-define=BRAND=xxx` (default: svid).
/// Access via [BrandConfig.current] — never changes at runtime.
abstract class BrandConfig {
  // ==================== SINGLETON ====================

  static BrandConfig? _current;

  /// The active brand configuration. Set once in main() via [BrandConfig.init].
  /// Auto-initializes with default brand (svid) on first access if [init] was
  /// not called — safe for tests that don't explicitly set up branding.
  static BrandConfig get current {
    _current ??= _resolve(
      Brand.fromString(
        const String.fromEnvironment('BRAND', defaultValue: 'svid'),
      ),
    );
    return _current!;
  }

  /// Initialize brand config from compile-time dart-define.
  /// Called in main() before runApp. Safe to call multiple times (first wins).
  static void init() {
    if (_current != null) return;
    const brandName = String.fromEnvironment('BRAND', defaultValue: 'svid');
    final brand = Brand.fromString(brandName);
    _current = _resolve(brand);
  }

  /// Override the active brand for a unit test. Tests that need to exercise
  /// brand-specific branches (PHP vs Go backend, tombstone helpers,
  /// brand-aware copy) call this in `setUp` and reset to null in `tearDown`.
  /// Production code never invokes this.
  @visibleForTesting
  static void setForTest(Brand? brand) {
    _current = brand == null ? null : _resolve(brand);
  }

  static BrandConfig _resolve(Brand brand) {
    // Lazy imports to avoid circular deps — these are lightweight data classes.
    final BrandConfig config;
    switch (brand) {
      case Brand.svid:
        config = const SvidBrand();
        break;
      case Brand.vidcombo:
        config = const VidComboBrand();
        break;
    }
    config._assertDatabaseNameInvariant();
    return config;
  }

  const BrandConfig();

  // ==================== IDENTITY ====================

  Brand get brand;
  String get appName;
  String get appDescription;

  /// SQLite database filename WITHOUT extension. The `.db` suffix is appended
  /// by [_openConnection] in `core/database/app_database.dart`.
  ///
  /// IMPORTANT: never include `.db` here. A regression in commit c8bbba91
  /// produced `'svid.db'` which then concatenated to `svid.db.db`, silently
  /// splitting users' download history into an orphan file.
  /// The base-class assertion in [_assertDatabaseNameInvariant] enforces this.
  String get databaseName;

  /// Defensive: every BrandConfig is validated at first access via
  /// [BrandConfig.current]. Subclasses must return [databaseName] without an
  /// extension; this method throws an [AssertionError] in debug builds and
  /// logs a warning in release builds if the contract is violated.
  void _assertDatabaseNameInvariant() {
    assert(
      !databaseName.contains('.'),
      'BrandConfig.databaseName must not contain "." — got "$databaseName". '
      'The .db extension is appended in app_database.dart. See c8bbba91 regression.',
    );
  }

  /// URL scheme for deep links (e.g., "svid" → svid://activate?key=...)
  String get urlScheme;

  /// Platform bundle ID / app ID
  String get bundleId;

  /// Windows taskbar identity. Usually matches [bundleId], but can differ when
  /// Windows shell cache or legacy pinned shortcuts require a new AUMID while
  /// preserving existing app data and license paths.
  String get windowsAppUserModelId;

  /// MethodChannel prefix for native communication
  String get methodChannelPrefix;

  // ==================== BACKEND ====================

  BackendType get backendType;

  /// Base URL for the brand's primary backend (PHP for VidCombo legacy, Go for Svid)
  String get backendBaseUrl;

  /// Base URL for the shared Go backend (identity, analytics, payment, support).
  /// All brands use the same Go backend for operational services.
  /// BackendClient (API key auth) always targets this URL.
  String get goBackendBaseUrl => const String.fromEnvironment(
    'GO_BACKEND_URL',
    defaultValue: 'https://api.svid.app/api/v1',
  );

  /// App name sent to backend for device registration (e.g., 'appVidcombo')
  String get backendAppName;

  /// Base URL for the video extraction API (svid.net/vidcombo.net backend)
  String get extractionApiUrl;

  /// Product website URL
  String get websiteUrl;

  /// URL for version check (null = uses brand-specific protocol)
  String? get versionCheckUrl;

  // ==================== PAYMENT ====================

  /// Whether Stripe checkout is available (system browser flow).
  /// All brands with a Go backend can use Stripe.
  bool get hasStripeCheckout;

  /// Whether VidCombo's PDFConv-backed PayPal checkout is available.
  bool get hasPdfConvPayPalCheckout => false;

  /// Whether app can auto-download update binaries (vs redirect to website)
  bool get canAutoDownloadUpdate;

  /// Free-tier weekly download quota for this brand.
  int get freeWeeklyDownloads;

  /// Whether ALL premium features are unlocked for every user (no monetization).
  ///
  /// When true, [PremiumLicenseService.isFeatureAvailable] short-circuits to
  /// `true`, which drives `isPremiumProvider` — so unlimited downloads, 8K,
  /// concurrency, batch, browser-shield/media-sniff and ad-block all open for
  /// free. svid ships free+unlimited; VidCombo keeps its paid tier (default
  /// false).
  bool get allFeaturesFree => false;

  // ==================== LICENSE ====================

  /// Regex pattern for validating license keys
  RegExp get licenseKeyPattern;

  /// Placeholder text for license key input field
  String get licenseKeyHint;

  /// Canonical license key format example shown in "invalid format" error.
  /// MUST be brand-specific — never embed cross-brand prefixes (e.g.
  /// VidCombo must NOT display 'SSVID-XXXX-...').
  String get licenseKeyFormatExample;

  /// Validate a license key against this brand's format
  bool isValidLicenseKey(String key) => licenseKeyPattern.hasMatch(key);

  // ==================== COLORS ====================

  BrandColors get colors;

  /// Light theme ColorScheme
  ColorScheme get lightColorScheme;

  /// Dark theme ColorScheme
  ColorScheme get darkColorScheme;

  // ==================== GRADIENTS ====================

  /// Primary brand gradient — CTAs, icon fills, accent borders
  LinearGradient get premiumGradient;

  /// Extended premium gradient with third color stop
  LinearGradient get premiumExtendedGradient;

  /// Subtle glow shadow for cards
  BoxShadow get glowSubtle;

  /// Intense glow for featured cards
  BoxShadow get glowIntense;

  /// CTA button glow shadow
  BoxShadow get glowCta;

  // ==================== THEME ====================

  /// Default theme mode for this brand.
  /// Svid: dark (Nocturne Cinematic). VidCombo: light (Arctic Clarity).
  ThemeMode get defaultThemeMode;

  // ==================== SHAPE ====================

  /// Card corner radius — cards, containers, panels, bottom sheets, snackbars
  double get cardRadius;

  /// Button corner radius — elevated, text, outlined, filled, icon, segmented, FAB
  double get buttonRadius;

  /// Input field corner radius — text fields, search bars, dropdown inputs
  double get inputRadius;

  /// Dialog corner radius — dialogs, date/time pickers
  double get dialogRadius;

  /// Chip corner radius — chips, tags, filter pills
  double get chipRadius;

  /// Popup corner radius — popup menus, context menus, tooltips, dropdown menus
  double get popupRadius;

  /// Card elevation — Svid: flat (0), VidCombo: subtle lift
  double get cardElevation;

  /// Whether cards/containers show visible borders.
  /// Svid: true (flat cards need borders to define edges)
  /// VidCombo: false (elevated cards use shadow instead)
  bool get hasCardBorder;

  // ==================== FLOATING CAPTURE POPUP (v2.2 Phase 2B) ====================

  /// Primary action background color in floating capture popup.
  /// Svid: Wine Red #8D021F (the rare, single accent presence).
  /// VidCombo: Ocean Blue #0066CC (decisive action commitment).
  ///
  /// Spec §7 brand parity rule: NEVER hardcode wine red in popup files —
  /// always read from `BrandConfig.current.popupAccentColor`.
  Color get popupAccentColor;

  /// Foreground color paired with [popupAccentColor] (button text/icons).
  /// Both brands ship pure white per Stitch design tokens.
  Color get popupAccentForeground;

  /// 8pt brand-dot circle in the popup top bar.
  /// Svid: same Wine Red as primary action (mono-accent palette).
  /// VidCombo: Cyan #03BEFE — DISTINCT from primary button (Ocean Blue).
  /// The 2-color play creates visual layering: dot=spark, button=mass.
  Color get popupBrandDot;

  /// Hover/active state of [popupAccentColor].
  /// Svid: Crimson #C41E3A. VidCombo: Cyan #03BEFE.
  Color get popupAccentHover;
}

// ==================== BRAND IMPLEMENTATIONS ====================
// Defined here to keep everything in one file and avoid import issues.

/// Svid brand — Nocturne Cinematic (Wine Red + Crimson)
class SvidBrand extends BrandConfig {
  const SvidBrand();

  @override
  Brand get brand => Brand.svid;
  @override
  String get appName => 'Svid';
  @override
  String get appDescription =>
      'High-performance video downloader powered by Rust + Flutter';
  @override
  String get databaseName => 'svid';
  @override
  String get urlScheme => 'svid';
  @override
  String get bundleId => 'com.svid.app';
  @override
  String get windowsAppUserModelId => 'com.svid.app';
  @override
  String get methodChannelPrefix => 'com.svid.app';

  @override
  BackendType get backendType => BackendType.go;
  @override
  String get backendBaseUrl => const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://api.svid.app/api/v1',
  );
  @override
  String get backendAppName => 'appSvid';
  @override
  String get extractionApiUrl => 'https://api.svid.app/';
  @override
  String get websiteUrl => 'https://svid.app';
  @override
  String? get versionCheckUrl => 'https://svid.app/version.json';
  @override
  bool get hasStripeCheckout => true;
  @override
  bool get canAutoDownloadUpdate => true;
  @override
  int get freeWeeklyDownloads => 15;
  @override
  bool get allFeaturesFree => true; // svid is free + unlimited for everyone

  @override
  RegExp get licenseKeyPattern =>
      RegExp(r'^SVID-[0-9A-Fa-f]{4}(-[0-9A-Fa-f]{4}){7}$');
  @override
  String get licenseKeyHint => 'SVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX';
  @override
  String get licenseKeyFormatExample =>
      'SVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX';
  // Svid validates only its own SVID- keys (base isValidLicenseKey =
  // licenseKeyPattern.hasMatch). Svid is an independent product — it does NOT
  // accept the separate ssvid product's SSVID- keys.

  @override
  ThemeMode get defaultThemeMode => ThemeMode.dark;

  // Shape — soft rounded corners aligned with the svid.app website
  // (buttons/inputs ~10, cards ~12, chips ~8, dialogs ~14).
  @override
  double get cardRadius => 12;
  @override
  double get buttonRadius => 10;
  @override
  double get inputRadius => 10;
  @override
  double get dialogRadius => 14;
  @override
  double get chipRadius => 8;
  @override
  double get popupRadius => 10;
  @override
  double get cardElevation => 0;
  @override
  bool get hasCardBorder => true;

  @override
  BrandColors get colors => const BrandColors(
    brand: Color(0xFF8D021F),
    brandLight: Color(0xFFD73555),
    brandDark: Color(0xFF5E0115),
    accentHighlight: Color(0xFFD73555),
    accentMuted: Color(0xFF6E0920),
    gradientStart: Color(0xFF8D021F),
    gradientEnd: Color(0xFFC81D3D),
    gradientMid: Color(0xFFA20827),
    gradientTail: Color(0xFFF4A7B5),
    // Architectural Gallery Morning — neutral gallery shell with wine accents
    lightMuted: Color(0xFFD8DEE5), // L4 outlineVariant hairline
    lightMetaText: Color(0xFF4B5159), // onSurfaceVariant, not pink-biased
    lightBase: Color(0xFFF7F8FA), // L1 app body neutral canvas
    lightElevated: Color(0xFFFFFFFF), // L0 most-elevated card
    // Obsidian Wine Cellar — neutral charcoal structure, wine only as accent
    darkMuted: Color(0xFF4A444C), // L outlineVariant hairline
    darkLightText: Color(0xFFF7F4F5), // onSurface
    darkMetaText: Color(0xFFC0BBC0), // onSurfaceVariant
    darkBase: Color(0xFF111216), // L1 app body, neutral charcoal
    darkElevated: Color(0xFF202127), // L3 default card
    // Mission Briefing — Nocturne operator surfaces & rotating accents
    darkSurfaceLowest: Color(0xFF07080A), // L0 deep inset well
    lightSurfaceLowest: Color(0xFFEEF1F4), // L3 recessed card
    accentSecondary: Color(0xFFF2A0AE), // rose — time/format icons
    accentTertiary: Color(0xFF80D5D1), // teal — additional options
    // Home Dark Operator Tokens — clear surface ladder for command UI
    homeDarkAppBg: Color(0xFF07080A), // root canvas — darkest
    homeDarkCardBg: Color(0xFF18191E), // card/panel surface
    homeDarkCardHover: Color(0xFF24252C), // hover lift
    homeDarkCardSelected: Color(0xFF2A1620), // wine-tinted selection well
    homeDarkCardActive: Color(0xFF1D0D16), // deep wine active/downloading
    homeDarkBorderSubtle: Color(0xFF2D2E36), // visible panel divider
    homeDarkBorderStrong: Color(0xFF464650), // control outline / separator
    homeDarkTextSecondary: Color(0xFFAFA9AE), // secondary text on card
    homeDarkTextMuted: Color(0xFF8F8992), // metadata on card
    homeDarkInputBorder: Color(0xFF5A5360), // default input outline
    homeDarkAccentSoft: Color(0xFF260B15), // wine accent well
  );

  @override
  ColorScheme get lightColorScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8D021F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFCDDE3),
    onPrimaryContainer: Color(0xFF3B0010),
    secondary: Color(0xFF546E7A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE0E7EC),
    onSecondaryContainer: Color(0xFF1E2D35),
    tertiary: Color(0xFF7C3AED),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEDE9FE),
    onTertiaryContainer: Color(0xFF4C1D95),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFF7F8FA),
    onSurface: Color(0xFF1B1C1F),
    onSurfaceVariant: Color(0xFF4B5159),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF2F4F6),
    surfaceContainer: Color(0xFFECEFF2),
    surfaceContainerHigh: Color(0xFFE5E9ED),
    surfaceContainerHighest: Color(0xFFDDE3E8),
    outline: Color(0xFFAEB7C2),
    outlineVariant: Color(0xFFD8DEE5),
    inverseSurface: Color(0xFF202127),
    onInverseSurface: Color(0xFFF7F4F5),
    inversePrimary: Color(0xFFF48B9B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF8D021F),
  );

  @override
  ColorScheme get darkColorScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF08EA0),
    onPrimary: Color(0xFF3F0010),
    primaryContainer: Color(0xFF7A071F),
    onPrimaryContainer: Color(0xFFFFD9DF),
    secondary: Color(0xFF90A4AE),
    onSecondary: Color(0xFF1E2D35),
    secondaryContainer: Color(0xFF37474F),
    onSecondaryContainer: Color(0xFFCFD8DC),
    tertiary: Color(0xFFA78BFA),
    onTertiary: Color(0xFF4C1D95),
    tertiaryContainer: Color(0xFF5B21B6),
    onTertiaryContainer: Color(0xFFEDE9FE),
    error: Color(0xFFFCA5A5),
    onError: Color(0xFF7F1D1D),
    errorContainer: Color(0xFF991B1B),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF111216),
    onSurface: Color(0xFFF7F4F5),
    onSurfaceVariant: Color(0xFFC0BBC0),
    surfaceContainerLowest: Color(0xFF07080A),
    surfaceContainerLow: Color(0xFF18191E),
    surfaceContainer: Color(0xFF202127),
    surfaceContainerHigh: Color(0xFF292A31),
    surfaceContainerHighest: Color(0xFF33333D),
    outline: Color(0xFF6B626D),
    outlineVariant: Color(0xFF464650),
    inverseSurface: Color(0xFFF7F4F5),
    onInverseSurface: Color(0xFF111216),
    inversePrimary: Color(0xFF8D021F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFFF08EA0),
  );

  @override
  LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8D021F), Color(0xFFBA1434)],
  );

  @override
  LinearGradient get premiumExtendedGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8D021F), Color(0xFF910621), Color(0xFFFFB3B4)],
  );

  @override
  BoxShadow get glowSubtle =>
      const BoxShadow(color: Color(0x1A8D021F), blurRadius: 40);

  @override
  BoxShadow get glowIntense =>
      const BoxShadow(color: Color(0x33BA1434), blurRadius: 60);

  @override
  BoxShadow get glowCta =>
      const BoxShadow(color: Color(0x668D021F), blurRadius: 20);

  // -- Floating capture popup tokens (v2.2 Phase 2B / Stitch Svid Nocturne) --
  @override
  Color get popupAccentColor => const Color(0xFF8D021F); // Wine Red
  @override
  Color get popupAccentForeground => const Color(0xFFFFFFFF);
  @override
  Color get popupBrandDot => const Color(0xFF8D021F);
  @override
  Color get popupAccentHover => const Color(0xFFC41E3A); // Crimson
}

/// VidCombo brand — Arctic Command (Cyan + Deep Blue + Navy)
class VidComboBrand extends BrandConfig {
  const VidComboBrand();

  @override
  Brand get brand => Brand.vidcombo;
  @override
  String get appName => 'VidCombo';
  @override
  String get appDescription =>
      'High-performance video downloader powered by Rust + Flutter';
  @override
  String get databaseName => 'vidcombo';
  @override
  String get urlScheme => 'vidcombo';
  @override
  String get bundleId => 'com.tinasoft.vidcombo';
  @override
  String get windowsAppUserModelId => 'com.tinasoft.vidcombo.desktop';
  @override
  String get methodChannelPrefix => 'com.tinasoft.vidcombo';

  @override
  BackendType get backendType => BackendType.php;
  @override
  String get backendBaseUrl => const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://api.vidcombo.net',
  );
  @override
  String get backendAppName => 'appVidcombo';
  @override
  String get extractionApiUrl => 'https://api.vidcombo.net/';
  @override
  String get websiteUrl => 'https://vidcombo.net';
  @override
  String? get versionCheckUrl => null; // Go backend is primary; no version.json fallback yet
  @override
  bool get hasStripeCheckout => true;
  @override
  bool get hasPdfConvPayPalCheckout => true;
  @override
  bool get canAutoDownloadUpdate => true;

  /// VidCombo unified to 15/week to match Svid. Server-side PHP
  /// `count_free` is legacy daily data; client tracking ignores it.
  @override
  int get freeWeeklyDownloads => 15;

  /// VidCombo accepts legacy PHP keys (32-char alphanumeric) and Go backend keys.
  ///
  /// The 32-char PHP gate is INTENTIONALLY permissive (any case): `checkkey.php`
  /// is the authoritative validator, so this client pattern must NOT be narrower
  /// than the real PHP key alphabet. Narrowing to hex/uppercase-only risks
  /// rejecting a paying user's key at the local format gate before the server is
  /// ever asked (AP-1 lockout). A doomed key just fails server-side — harmless.
  @override
  RegExp get licenseKeyPattern => RegExp(r'^[0-9A-Za-z]{32}$');
  @override
  String get licenseKeyHint => 'Enter your license key';
  @override
  String get licenseKeyFormatExample =>
      'VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX';

  /// Accept legacy PHP keys, VIDCOMBO-XXXX (Go new), and SSVID-XXXX (Go legacy)
  @override
  bool isValidLicenseKey(String key) {
    // Legacy PHP format: 32 hex chars (case-insensitive) or 32 uppercase
    // alphanumeric chars for admin-created manual keys.
    if (licenseKeyPattern.hasMatch(key)) return true;
    // Go backend format (new): VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (48 chars)
    if (key.startsWith('VIDCOMBO-') && key.length == 48) return true;
    // Go backend format (legacy — keys generated before brand separation): SSVID-XXXX-... (45 chars)
    if (key.startsWith('SSVID-') && key.length == 45) return true;
    return false;
  }

  @override
  ThemeMode get defaultThemeMode => ThemeMode.light;

  // Shape — rounded, frosted glass (Arctic Command)
  @override
  double get cardRadius => 12;
  @override
  double get buttonRadius => 999;
  @override
  double get inputRadius => 8;
  @override
  double get dialogRadius => 12;
  @override
  double get chipRadius => 999;
  @override
  double get popupRadius => 8;
  @override
  double get cardElevation => 2;
  @override
  bool get hasCardBorder => false;

  // Arctic Command: Cyan #03BEFE, Deep Blue #0066CC, Navy #0041CC, Accent #7DB1FF
  @override
  BrandColors get colors => const BrandColors(
    brand: Color(0xFF0066CC),
    brandLight: Color(0xFF03BEFE),
    brandDark: Color(0xFF0041CC),
    accentHighlight: Color(0xFF03BEFE),
    accentMuted: Color(0xFF003D99),
    gradientStart: Color(0xFF0066CC),
    gradientEnd: Color(0xFF03BEFE),
    gradientMid: Color(0xFF0041CC),
    gradientTail: Color(0xFF7DB1FF),
    // Nordic Studio Noon — pale ice light UI
    lightMuted: Color(0xFFC1C6D5), // L outlineVariant hairline
    lightMetaText: Color(0xFF2F3640), // darker metadata for stronger contrast
    lightBase: Color(0xFFF5F6F8), // neutral app body background
    lightElevated: Color(0xFFFFFFFF), // L0 most-elevated card
    // Arctic Obsidian Command — cool slate dark UI (Pillar #1 + #2)
    darkMuted: Color(0xFF3D4850), // L outlineVariant hairline
    darkLightText: Color(0xFFF2F4F7), // onSurface (Pillar #5, 14.8:1)
    darkMetaText: Color(0xFFBCC8D1), // onSurfaceVariant (9.4:1)
    darkBase: Color(
      0xFF141618,
    ), // L1 app body (lifted +0.12 L* for empty-canvas breathing room)
    darkElevated: Color(
      0xFF282A2E,
    ), // L3 default card (v1.0.2 lift for card pop)
    // Mission Briefing — Arctic operator surfaces & rotating accents
    darkSurfaceLowest: Color(0xFF0D0E10), // L0 deep inset well
    lightSurfaceLowest: Color(0xFFEBEEF1), // L3 recessed card
    accentSecondary: Color(0xFF7DB1FF), // soft cyan — time/format icons
    accentTertiary: Color(0xFFAAC7FF), // ice blue — additional options
    // Home Dark Operator Tokens — Cold Operator (Palette A)
    homeDarkAppBg: Color(0xFF0D0F11), // root canvas — darkest
    homeDarkCardBg: Color(0xFF1C2026), // card surface — 7 L* above panel
    homeDarkCardHover: Color(0xFF252B32), // hover — +2.5 L*, immediate
    homeDarkCardSelected: Color(0xFF1B2D42), // blue-tinted selection well
    homeDarkCardActive: Color(0xFF0F2336), // deep blue active/downloading
    homeDarkBorderSubtle: Color(0xFF1E2328), // hairline divider
    homeDarkBorderStrong: Color(0xFF2E3640), // input outline, separator
    homeDarkTextSecondary: Color(0xFF8B96A3), // 5.8:1 on card ✅ AA
    homeDarkTextMuted: Color(0xFF7A8694), // 4.8:1 on card ✅ AA
    homeDarkInputBorder: Color(0xFF2A3038), // subtle input default
    homeDarkAccentSoft: Color(0xFF0A2438), // accent background well
  );

  @override
  ColorScheme get lightColorScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0066CC),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6E8FF),
    onPrimaryContainer: Color(0xFF001D3A),
    secondary: Color(0xFF546E7A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF00BDFD),
    onSecondaryContainer: Color(0xFF001D3A),
    tertiary: Color(0xFF7C3AED),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFEDE9FE),
    onTertiaryContainer: Color(0xFF4C1D95),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFF5F6F8),
    onSurface: Color(0xFF181C1E),
    onSurfaceVariant: Color(0xFF2F3640),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F4F7),
    surfaceContainer: Color(0xFFEBEEF1),
    surfaceContainerHigh: Color(0xFFE5E8EB),
    surfaceContainerHighest: Color(0xFFE0E3E6),
    outline: Color(0xFF8E97A1),
    outlineVariant: Color(0xFFC1C6D5),
    inverseSurface: Color(0xFF282A2E),
    onInverseSurface: Color(0xFFF2F4F7),
    inversePrimary: Color(0xFF8DD6FF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF0066CC),
  );

  @override
  ColorScheme get darkColorScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8DD6FF),
    onPrimary: Color(0xFF003549),
    primaryContainer: Color(0xFF004A99),
    onPrimaryContainer: Color(0xFFD6E8FF),
    secondary: Color(0xFF90A4AE),
    onSecondary: Color(0xFF1E2D35),
    secondaryContainer: Color(0xFF37474F),
    onSecondaryContainer: Color(0xFFCFD8DC),
    tertiary: Color(0xFFA78BFA),
    onTertiary: Color(0xFF4C1D95),
    tertiaryContainer: Color(0xFF5B21B6),
    onTertiaryContainer: Color(0xFFEDE9FE),
    error: Color(0xFFFCA5A5),
    onError: Color(0xFF7F1D1D),
    errorContainer: Color(0xFF991B1B),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF141618),
    onSurface: Color(0xFFF2F4F7),
    onSurfaceVariant: Color(0xFFBCC8D1),
    surfaceContainerLowest: Color(0xFF0D0E10),
    surfaceContainerLow: Color(0xFF1E2023),
    surfaceContainer: Color(0xFF282A2E),
    surfaceContainerHigh: Color(0xFF32353A),
    surfaceContainerHighest: Color(0xFF3D4045),
    outline: Color(0xFF5A6169),
    outlineVariant: Color(0xFF3D4850),
    inverseSurface: Color(0xFFF2F4F7),
    onInverseSurface: Color(0xFF141618),
    inversePrimary: Color(0xFF0066CC),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF8DD6FF),
  );

  @override
  LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0066CC), Color(0xFF03BEFE)],
  );

  @override
  LinearGradient get premiumExtendedGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0041CC), Color(0xFF0066CC), Color(0xFF7DB1FF)],
  );

  @override
  BoxShadow get glowSubtle =>
      const BoxShadow(color: Color(0x1A0066CC), blurRadius: 40);

  @override
  BoxShadow get glowIntense =>
      const BoxShadow(color: Color(0x3303BEFE), blurRadius: 60);

  @override
  BoxShadow get glowCta =>
      const BoxShadow(color: Color(0x660066CC), blurRadius: 20);

  // -- Floating capture popup tokens (v2.2 Phase 2B / Stitch Arctic Command) --
  // Two-color play DISTINCT from Svid: brand dot is Cyan #03BEFE (the spark),
  // primary action is Ocean Blue #0066CC (the mass). Verified `brand_config.dart`
  // gradient line 795 (now embedded in colors list above).
  @override
  Color get popupAccentColor => const Color(0xFF0066CC); // Ocean Blue
  @override
  Color get popupAccentForeground => const Color(0xFFFFFFFF);
  @override
  Color get popupBrandDot => const Color(0xFF03BEFE); // Cyan — distinct from button
  @override
  Color get popupAccentHover => const Color(0xFF03BEFE); // Cyan
}
