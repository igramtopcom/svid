/// Represents a single browsing history entry
class BrowserHistoryEntry {
  final String id;
  final String url;
  final String title;
  final DateTime visitedAt;

  const BrowserHistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  BrowserHistoryEntry copyWith({
    String? title,
    DateTime? visitedAt,
  }) {
    return BrowserHistoryEntry(
      id: id,
      url: url,
      title: title ?? this.title,
      visitedAt: visitedAt ?? this.visitedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory BrowserHistoryEntry.fromJson(Map<String, dynamic> json) =>
      BrowserHistoryEntry(
        id: json['id'] as String,
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        visitedAt: DateTime.parse(json['visitedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserHistoryEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
