import 'package:flutter/material.dart';
import '../config/brand_config.dart';

/// Design System — Gradient Palette v1.1 (Brand-Aware)
/// Gradients delegate to [BrandConfig.current] for brand-specific colors.
class AppGradients {
  AppGradients._();

  // ==================== PREMIUM ====================

  /// Primary brand gradient — CTAs, icon fills, text clips, accent borders.
  static LinearGradient get premium => BrandConfig.current.premiumGradient;

  /// Extended premium gradient with third color stop — celebration screens, hero CTAs.
  static LinearGradient get premiumExtended =>
      BrandConfig.current.premiumExtendedGradient;

  // ==================== GLOW SHADOWS ====================

  /// Subtle glow for cards and containers.
  static BoxShadow get glowSubtle => BrandConfig.current.glowSubtle;

  /// Intense glow for hero/featured cards.
  static BoxShadow get glowIntense => BrandConfig.current.glowIntense;

  /// CTA button glow shadow.
  static BoxShadow get glowCta => BrandConfig.current.glowCta;
}
