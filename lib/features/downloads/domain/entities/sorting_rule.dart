/// A user-defined rule for automatically sorting and renaming completed downloads.
///
/// Rules are evaluated in priority order (lower [order] = higher priority).
/// The first matching rule is applied; remaining rules are skipped.
class SortingRule {
  final String id; // UUID-like unique key
  final String name;
  final SortingCondition condition;
  final String destFolder; // absolute path; empty = same folder, no move
  final String renameTemplate; // e.g. "{title} - {uploader} ({date}).{ext}"
  final bool isEnabled;
  final int order; // sort order among rules

  const SortingRule({
    required this.id,
    required this.name,
    required this.condition,
    required this.destFolder,
    required this.renameTemplate,
    this.isEnabled = true,
    this.order = 0,
  });

  SortingRule copyWith({
    String? id,
    String? name,
    SortingCondition? condition,
    String? destFolder,
    String? renameTemplate,
    bool? isEnabled,
    int? order,
  }) {
    return SortingRule(
      id: id ?? this.id,
      name: name ?? this.name,
      condition: condition ?? this.condition,
      destFolder: destFolder ?? this.destFolder,
      renameTemplate: renameTemplate ?? this.renameTemplate,
      isEnabled: isEnabled ?? this.isEnabled,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'condition': condition.toJson(),
        'destFolder': destFolder,
        'renameTemplate': renameTemplate,
        'isEnabled': isEnabled,
        'order': order,
      };

  factory SortingRule.fromJson(Map<String, dynamic> json) => SortingRule(
        id: json['id'] as String,
        name: json['name'] as String,
        condition: SortingCondition.fromJson(
            json['condition'] as Map<String, dynamic>),
        destFolder: json['destFolder'] as String? ?? '',
        renameTemplate: json['renameTemplate'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
        order: json['order'] as int? ?? 0,
      );
}

/// Condition that determines whether a [SortingRule] applies to a download.
///
/// All non-empty/non-null fields must match (AND logic).
/// Empty/null fields are ignored (wildcard).
class SortingCondition {
  /// Match by platform string (e.g. 'youtube', 'tiktok'). Case-insensitive.
  /// Empty string = match any.
  final String platform;

  /// Match by file extension (e.g. 'mp4', 'mp3'). Case-insensitive.
  /// Empty string = match any.
  final String fileExtension;

  /// Match if the URL contains this substring. Empty = match any.
  final String urlContains;

  const SortingCondition({
    this.platform = '',
    this.fileExtension = '',
    this.urlContains = '',
  });

  bool get isWildcard =>
      platform.isEmpty && fileExtension.isEmpty && urlContains.isEmpty;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'fileExtension': fileExtension,
        'urlContains': urlContains,
      };

  factory SortingCondition.fromJson(Map<String, dynamic> json) =>
      SortingCondition(
        platform: json['platform'] as String? ?? '',
        fileExtension: json['fileExtension'] as String? ?? '',
        urlContains: json['urlContains'] as String? ?? '',
      );

  SortingCondition copyWith({
    String? platform,
    String? fileExtension,
    String? urlContains,
  }) =>
      SortingCondition(
        platform: platform ?? this.platform,
        fileExtension: fileExtension ?? this.fileExtension,
        urlContains: urlContains ?? this.urlContains,
      );
}
