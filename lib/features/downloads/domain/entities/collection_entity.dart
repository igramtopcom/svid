import 'download_entity.dart';

/// Filter criteria for a Smart Collection.
/// All non-empty/non-null fields must match (AND logic).
class CollectionFilter {
  /// Comma-separated or list of platforms to include. Empty = any.
  final List<String> platforms;

  /// Status strings to include (e.g. 'completed', 'failed'). Empty = any.
  final List<String> statuses;

  /// Tags the download must have (ALL of them). Empty = any.
  final List<String> tags;

  const CollectionFilter({
    this.platforms = const [],
    this.statuses = const [],
    this.tags = const [],
  });

  bool get isEmpty =>
      platforms.isEmpty && statuses.isEmpty && tags.isEmpty;

  Map<String, dynamic> toJson() => {
        'platforms': platforms,
        'statuses': statuses,
        'tags': tags,
      };

  factory CollectionFilter.fromJson(Map<String, dynamic> json) =>
      CollectionFilter(
        platforms: (json['platforms'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        statuses: (json['statuses'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  CollectionFilter copyWith({
    List<String>? platforms,
    List<String>? statuses,
    List<String>? tags,
  }) =>
      CollectionFilter(
        platforms: platforms ?? this.platforms,
        statuses: statuses ?? this.statuses,
        tags: tags ?? this.tags,
      );
}

/// A user-defined collection that groups downloads by filter criteria.
class CollectionEntity {
  final String id; // UUID-like key
  final String name;
  final String description;
  final CollectionFilter filter;
  final DateTime createdAt;

  const CollectionEntity({
    required this.id,
    required this.name,
    this.description = '',
    required this.filter,
    required this.createdAt,
  });

  /// Count downloads that match this collection's filter.
  int itemCount(
    List<DownloadEntity> downloads,
    Map<int, List<String>> tagsMap,
  ) =>
      downloads.where((d) => matchesFilter(d, tagsMap)).length;

  /// Returns true if [download] satisfies all non-empty filter criteria.
  bool matchesFilter(
    DownloadEntity download,
    Map<int, List<String>> tagsMap,
  ) {
    if (filter.platforms.isNotEmpty &&
        !filter.platforms
            .map((p) => p.toLowerCase())
            .contains(download.platform.toLowerCase())) {
      return false;
    }

    if (filter.statuses.isNotEmpty &&
        !filter.statuses.contains(download.status.name)) {
      return false;
    }

    if (filter.tags.isNotEmpty) {
      final downloadTags = tagsMap[download.id] ?? [];
      if (!filter.tags.every((t) => downloadTags.contains(t))) return false;
    }

    return true;
  }

  CollectionEntity copyWith({
    String? id,
    String? name,
    String? description,
    CollectionFilter? filter,
    DateTime? createdAt,
  }) =>
      CollectionEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        filter: filter ?? this.filter,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'filter': filter.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory CollectionEntity.fromJson(Map<String, dynamic> json) =>
      CollectionEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        filter: CollectionFilter.fromJson(
            json['filter'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
