import 'package:flutter/material.dart';

import '../config/brand_config.dart';

/// Design System Typography — brand-aware font selection
/// Svid: Inter — Nocturne Cinematic (humanist, sharp terminals)
/// VidCombo: DM Sans — Arctic Command (geometric-friendly, clear bold)
class AppTypography {
  AppTypography._();

  /// Primary font family — used as ThemeData root fontFamily
  static String get fontFamily {
    switch (BrandConfig.current.brand) {
      case Brand.svid:
        return 'Inter';
      case Brand.vidcombo:
        return 'DM Sans';
    }
  }

  /// Fallback font family
  static const String fallbackFontFamily = 'Roboto';
  static const List<String> fallbackFontFamilies = [
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    // CJK system fonts (zero bundle cost) — Flutter walks the fallback list
    // per-glyph, so Latin text resolves above and only CJK codepoints reach
    // these. Bundled brand fonts (Inter/DM Sans) carry no CJK glyphs, so
    // without this the translated ja/ko/zh strings render as tofu boxes on
    // Windows. Covers JP/KR/CN across macOS, Windows and Linux.
    'Hiragino Sans', // macOS JP
    'Yu Gothic', // Windows JP
    'Meiryo', // Windows JP (legacy)
    'Apple SD Gothic Neo', // macOS KR
    'Malgun Gothic', // Windows KR
    'PingFang SC', // macOS CN
    'Microsoft YaHei', // Windows CN
    'Noto Sans CJK JP', // Linux (and any system with Noto CJK)
    'sans-serif',
  ];

  // ==================== FONT WEIGHTS ====================
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // ==================== INTERNAL FONT HELPER ====================

  /// Brand font — single font per brand, all contexts
  static TextStyle _font({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fallbackFontFamilies,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // ==================== TEXT THEME ====================

  static TextTheme get textTheme {
    const baseStyles = TextTheme(
      // Display
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.12,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.16,
        letterSpacing: -0.25,
      ),
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        height: 1.22,
      ),

      // Headline
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.29,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.33,
      ),

      // Title
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.27,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.50,
        letterSpacing: 0.1,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.43,
        letterSpacing: 0.1,
      ),

      // Label
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.43,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.33,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.45,
        letterSpacing: 0.3,
      ),

      // Body
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.50,
        letterSpacing: 0.15,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0.15,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.33,
        letterSpacing: 0.2,
      ),
    );

    return baseStyles.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fallbackFontFamilies,
    );
  }

  // ==================== CUSTOM STYLES ====================

  static TextStyle get appBarTitle =>
      _font(fontSize: 16, fontWeight: semiBold, height: 1.4);

  static TextStyle get sectionHeader => _font(
    fontSize: 11,
    fontWeight: semiBold,
    height: 1.45,
    letterSpacing: 1.2,
  );

  static TextStyle get fileName =>
      _font(fontSize: 14, fontWeight: medium, height: 1.43);

  static TextStyle get metadata => _font(
    fontSize: 12,
    fontWeight: regular,
    height: 1.38,
    letterSpacing: 0.15,
  );

  static TextStyle get buttonPrimary => _font(
    fontSize: 13,
    fontWeight: semiBold,
    height: 1.43,
    letterSpacing: 0.1,
  );

  static TextStyle get buttonSecondary =>
      _font(fontSize: 13, fontWeight: medium, height: 1.43, letterSpacing: 0.1);

  static TextStyle get input => _font(
    fontSize: 14,
    fontWeight: regular,
    height: 1.50,
    letterSpacing: 0.1,
  );

  static TextStyle get inputHint => _font(
    fontSize: 14,
    fontWeight: regular,
    height: 1.50,
    letterSpacing: 0.1,
  );

  static TextStyle get platformName =>
      _font(fontSize: 13, fontWeight: medium, height: 1.43);

  static TextStyle get statusBadge => _font(
    fontSize: 11,
    fontWeight: semiBold,
    height: 1.33,
    letterSpacing: 0.3,
  );

  static TextStyle get navItem =>
      _font(fontSize: 13, fontWeight: medium, height: 1.43);

  static TextStyle get navItemSelected =>
      _font(fontSize: 13, fontWeight: semiBold, height: 1.43);

  /// Compact text — dense metadata, file sizes, timestamps (11px)
  /// Same size as labelSmall but tighter lineHeight for data-dense contexts.
  /// Cross-platform safe: M3 floor + Inter design target.
  static TextStyle get compact =>
      _font(fontSize: 11, fontWeight: medium, height: 1.40, letterSpacing: 0.3);

  /// Mini label — uppercase decorative badges, tiny indicators (10px)
  /// Absolute minimum for readable text. Aligns with macOS Footnote.
  /// Use sparingly — only for short uppercase labels with letter-spacing.
  static TextStyle get mini => _font(
    fontSize: 10,
    fontWeight: semiBold,
    height: 1.33,
    letterSpacing: 0.4,
  );

  // ==================== MISSION BRIEFING — operator-grade ====================
  // Consolidated typography palette for the download config dialog and other
  // "command console" surfaces. Brand-aware font selection via _h/_b helpers.
  //
  // Hierarchy:
  //   commandTitle  18px w900  →  modal header
  //   briefingSection 14px w900 → section headers
  //   briefingCardTitle 13px w800 → card titles + dropdown values
  //   briefingAction 12px w900 → buttons (with letter-spacing)
  //   monoData 11px w700 → file sizes, timestamps (body font, not mono — keeps single family)
  //   microLabel 10px w900 → form labels, eyebrows, small caps (letter-spacing varies)
  //   briefingMicroBadge 9px w900 → tiny pill badges (PRO, codec, AUTO, max badge)
  //   briefingCardSubtitle 10px w500 → card descriptors (lighter — less visual noise)

  /// Command title — modal headers like "MISSION BRIEFING" (18px / w900 / -0.5)
  static TextStyle get commandTitle => _font(
    fontSize: 18,
    fontWeight: FontWeight.w900,
    height: 1.0,
    letterSpacing: -0.5,
  );

  /// Section heading — "VIDEO QUALITY", "FORMAT" (14px / w900 / -0.2)
  static TextStyle get briefingSection => _font(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    height: 1.1,
    letterSpacing: -0.2,
  );

  /// Card title — "1440P 60FPS", "AAC · 129KBPS" (13px / w800 / -0.1)
  /// Slightly lighter than briefingSection so cards feel like content, not headers.
  static TextStyle get briefingCardTitle => _font(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.1,
  );

  /// Card subtitle — "Quad HD • High Frame Rate" (11px / w500 / +0.2)
  /// Bumped 10→11 so the densest-info line clears the comfortable-read floor.
  /// Weight stays w500 so descriptors don't compete with the w800 title.
  static TextStyle get briefingCardSubtitle => _font(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.2,
  );

  /// Micro label — form labels, eyebrows, "SELECTED N", section captions
  /// (10px / w900). Default letter-spacing is 1.5; callers may override
  /// (e.g. eyebrow uses 2.0 for inscription feel).
  static TextStyle get microLabel => _font(
    fontSize: 10,
    fontWeight: FontWeight.w900,
    height: 1.2,
    letterSpacing: 1.5,
  );

  /// Mono data — file sizes, timestamps, dropdown values (11px / w700 / +0.2).
  /// Uses body font (NOT a separate mono family) to avoid visual font-family
  /// clash inside the dialog. Tight letter-spacing gives a tabular feel.
  static TextStyle get monoData => _font(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.2,
  );

  /// Tiny pill badge — PRO, codec, AUTO, max-resolution (9px / w900 / +0.6).
  /// Single token replacing 7+ inline TextStyle() definitions across the dialog.
  /// Override letterSpacing/fontSize when needed.
  static TextStyle get briefingMicroBadge => _font(
    fontSize: 9,
    fontWeight: FontWeight.w900,
    height: 1.4,
    letterSpacing: 0.6,
  );

  /// Action button — ABORT / INITIALIZE DOWNLOAD (12px / w900 / +1.2)
  static TextStyle get briefingAction => _font(
    fontSize: 12,
    fontWeight: FontWeight.w900,
    height: 1.0,
    letterSpacing: 1.2,
  );
}
