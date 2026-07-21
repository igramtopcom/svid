import 'conversion_config.dart';

/// Category for organizing presets in the UI.
enum PresetCategory {
  format('Format'),
  device('Devices'),
  social('Social Media'),
  audio('Audio'),
  advanced('Advanced'),
  enhance('Enhance'),
  edit('Edit'),
  creative('Creative'),
  tools('Tools'),
  custom('Custom');

  final String displayName;
  const PresetCategory(this.displayName);
}

/// A named conversion preset with pre-configured settings.
///
/// Presets provide quick-access conversion profiles for common use cases
/// like device optimization, social media, audio extraction,
/// enhancement, editing, and creative effects.
class ConversionPreset {
  /// Unique identifier for this preset
  final String id;

  /// Display name (used as localization key when prefixed with "converter.presets.")
  final String name;

  /// Icon name from Material Icons
  final String icon;

  /// Short description
  final String description;

  /// The conversion configuration this preset applies
  final ConversionConfig config;

  /// UI grouping category
  final PresetCategory category;

  /// Whether this preset requires Premium subscription
  final bool isPremium;

  /// Whether this preset is curated as "popular" / most commonly used.
  /// Surfaces a small POPULAR badge in the UI to help new users
  /// discover the recommended starting points without analysis paralysis.
  final bool isPopular;

  const ConversionPreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.config,
    required this.category,
    this.isPremium = false,
    this.isPopular = false,
  });

  ConversionPreset copyWith({
    String? id,
    String? name,
    String? icon,
    String? description,
    ConversionConfig? config,
    PresetCategory? category,
    bool? isPremium,
    bool? isPopular,
  }) {
    return ConversionPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      config: config ?? this.config,
      category: category ?? this.category,
      isPremium: isPremium ?? this.isPremium,
      isPopular: isPopular ?? this.isPopular,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConversionPreset && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ConversionPreset($id, $name, premium=$isPremium)';
}
